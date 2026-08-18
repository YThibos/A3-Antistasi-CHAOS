<#
.SYNOPSIS
    Static syntax checker for Arma 3 SQF files. No external dependencies (pure PowerShell 5.1+/7+).

.DESCRIPTION
    Lexes SQF (comments, single/double quoted strings, preprocessor directives, macros)
    and reports structural syntax problems that would otherwise only surface as a
    silent script failure or a cryptic .rpt line at runtime.

    Findings are either ERROR (certain: the file cannot parse) or WARN (very likely wrong,
    but SQF's context-free-ish grammar leaves a little room for a false positive).

    Codes:
      E001  Mismatched bracket: closer does not match the open bracket
      E002  Unclosed bracket at end of file
      E003  Stray closing bracket with nothing open
      E004  Unterminated string or block comment / unexpected character
      E005  Unbalanced preprocessor conditional (#if/#ifdef/#ifndef vs #endif)
      E006  ';' before 'else' - terminates the if-statement early
      E007  ';' used as a separator inside an array literal '[ ]'
      W001  Probable missing ';' after a '}' code block
      W002  ',' used at code-block scope inside '{ }'
      W003  Single '=' inside an if/while condition (assignment, not comparison)
      W004  Assignment to an undeclared local variable (-Strict only)

.PARAMETER Path
    Files or directories to check. Directories are searched recursively for *.sqf.
    Defaults to the repository root.

.PARAMETER Changed
    Check only files changed against the merge base with the given ref (default: HEAD).

.PARAMETER Staged
    Check only files staged in git.

.PARAMETER Baseline
    Path to a baseline file of accepted pre-existing findings; matching findings are hidden.
    Defaults to Tools/sqfcheck/baseline.txt when that file exists.

.PARAMETER UpdateBaseline
    Rewrite the baseline file from the current findings instead of reporting them.

.PARAMETER Strict
    Enable extra style/robustness checks (W004).

.PARAMETER WarningsAsErrors
    Exit non-zero when only warnings were found.

.PARAMETER Quiet
    Print only findings and the summary line.

.PARAMETER Json
    Emit findings as JSON on stdout instead of text.

.EXAMPLE
    pwsh -File Tools/sqfcheck/Check-Sqf.ps1 -Changed

.EXAMPLE
    pwsh -File Tools/sqfcheck/Check-Sqf.ps1 A3A/addons/core/functions/AI/fn_airbomb.sqf

.NOTES
    Exit codes: 0 = clean (or warnings only), 1 = errors found, 2 = bad invocation.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Path,
    [string] $Changed,
    [switch] $Staged,
    [string] $Baseline,
    [switch] $UpdateBaseline,
    [switch] $Strict,
    [switch] $WarningsAsErrors,
    [switch] $Quiet,
    [switch] $Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# ---------------------------------------------------------------- lexer ----

# One master regex, so a 20 MB codebase still lexes in seconds.
$script:TokenRegex = [regex]::new(
    @'
(?<lc>//[^\r\n]*)
|(?<bc>/\*.*?(\*/|\z))
|(?<dq>"(?:[^"]|"")*")
|(?<sq>'(?:[^']|'')*')
|(?<pp>(?<=^[ \t]*)\#[A-Za-z_]+(?:[^\r\n\\]|\\\r?\n|\\[^\r\n])*)
|(?<num>0[xX][0-9a-fA-F]+|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)
|(?<id>[A-Za-z_][A-Za-z0-9_]*)
|(?<br>[\(\)\[\]\{\}])
|(?<op>==|!=|>=|<=|>>|&&|\|\||[-+*/%^=<>!\#:,;?.\\])
|(?<ws>\s+)
'@,
    [System.Text.RegularExpressions.RegexOptions]::IgnorePatternWhitespace -bor
    [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
    [System.Text.RegularExpressions.RegexOptions]::Multiline -bor
    [System.Text.RegularExpressions.RegexOptions]::Compiled)

# A class rather than [pscustomobject]: millions of tokens are built on a full-repo scan.
class SqfToken {
    [string] $Kind
    [string] $Text
    [int] $Index
    SqfToken([string] $kind, [string] $text, [int] $index) {
        $this.Kind = $kind; $this.Text = $text; $this.Index = $index
    }
}

$script:NewlineRegex = [regex]::new("`n", [System.Text.RegularExpressions.RegexOptions]::Compiled)

function Get-LineStarts([string] $Text) {
    $starts = [System.Collections.Generic.List[int]]::new()
    $starts.Add(0) | Out-Null
    foreach ($m in $script:NewlineRegex.Matches($Text)) { $starts.Add($m.Index + 1) | Out-Null }
    return $starts
}

function Get-LineCol([System.Collections.Generic.List[int]] $Starts, [int] $Index) {
    $lo = 0; $hi = $Starts.Count - 1
    while ($lo -lt $hi) {
        $mid = [int](($lo + $hi + 1) / 2)
        if ($Starts[$mid] -le $Index) { $lo = $mid } else { $hi = $mid - 1 }
    }
    return @{ Line = $lo + 1; Col = $Index - $Starts[$lo] + 1 }
}

# Tokens that may legally follow a '}' without an intervening ';'.
# Mostly binary commands that take CODE on their left, plus operators and structure.
$script:AfterBlockOk = @(
    'and','or','not','then','else','do','count','each','forEach','forEachReversed',
    'exitWith','in','call','callExtension','spawn','execVM','execFSM','catch','try',
    'param','params','select','apply','findIf','sort','sortBy','from','to','step',
    'isEqualTo','isEqualToAny','isEqualType','isNil','configClasses','remoteExec',
    'remoteExecCall','pushBack','append','joinString','arrayIntersect','inAreaArray',
    'while','switch','case','default','for','if','with','private','catch','waitUntil',
    'canSuspend','deleteAt','deleteRange','set','splitString','regexFind','regexMatch'
) | ForEach-Object { $_.ToLowerInvariant() }
$script:AfterBlockOkSet = [System.Collections.Generic.HashSet[string]]::new(
    [string[]] $script:AfterBlockOk, [System.StringComparer]::OrdinalIgnoreCase)

$script:ConditionKeywords = [System.Collections.Generic.HashSet[string]]::new(
    [string[]] @('if','while','waitUntil'), [System.StringComparer]::OrdinalIgnoreCase)

$script:DeclKeywords = [System.Collections.Generic.HashSet[string]]::new(
    [string[]] @('private','params','param'), [System.StringComparer]::OrdinalIgnoreCase)

function New-Finding($File, $Line, $Col, $Level, $Code, $Message, $Source) {
    [pscustomobject]@{
        File    = $File
        Line    = $Line
        Col     = $Col
        Level   = $Level
        Code    = $Code
        Message = $Message
        Source  = $Source
    }
}

function Test-SqfFile([string] $FilePath, [bool] $StrictMode) {
    $rel = $FilePath
    if ($FilePath.StartsWith($script:RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $FilePath.Substring($script:RepoRoot.Length).TrimStart('\', '/')
    }
    $rel = $rel -replace '\\', '/'

    $text = [System.IO.File]::ReadAllText($FilePath)
    $starts = Get-LineStarts $text
    $lines = @($text -split "\r?\n")
    $findings = [System.Collections.Generic.List[object]]::new()

    function Add-Finding($Index, $Level, $Code, $Message) {
        $pos = Get-LineCol $starts $Index
        $src = ''
        if ($pos.Line -le $lines.Count) { $src = $lines[$pos.Line - 1].Trim() }
        $findings.Add((New-Finding $rel $pos.Line $pos.Col $Level $Code $Message $src)) | Out-Null
    }

    # --- tokenize, and detect anything the lexer could not account for -------
    $tokens = [System.Collections.Generic.List[object]]::new()
    $cursor = 0
    foreach ($m in $script:TokenRegex.Matches($text)) {
        if ($m.Index -gt $cursor) {
            $bad = $text.Substring($cursor, $m.Index - $cursor)
            if ($bad.Trim().Length -gt 0) {
                Add-Finding $cursor 'ERROR' 'E004' ("Unexpected character sequence '{0}' (unterminated string?)" -f $bad.Trim().Substring(0, [Math]::Min(20, $bad.Trim().Length)))
            }
        }
        $cursor = $m.Index + $m.Length

        # Classify by first character - far cheaper than probing nine named groups per token.
        $val = $m.Value
        $c0 = $val[0]
        $kind = 'op'
        if ([char]::IsWhiteSpace($c0)) {
            continue
        } elseif ($c0 -eq '/') {
            if ($val.Length -gt 1 -and $val[1] -eq '*') {
                if (-not $val.EndsWith('*/')) {
                    Add-Finding $m.Index 'ERROR' 'E004' 'Unterminated block comment /* ... */'
                }
            }
            continue                                  # comments carry no syntax
        } elseif ($c0 -eq '"') { $kind = 'dq' }
        elseif ($c0 -eq "'") { $kind = 'sq' }
        elseif ($c0 -eq '#') { if ($val.Length -gt 1 -and [char]::IsLetter($val[1])) { $kind = 'pp' } }
        elseif ([char]::IsDigit($c0) -or $c0 -eq '.') { $kind = 'num' }
        elseif ([char]::IsLetter($c0) -or $c0 -eq '_') { $kind = 'id' }
        elseif ('()[]{}'.IndexOf($c0) -ge 0) { $kind = 'br' }

        $tokens.Add([SqfToken]::new($kind, $val, $m.Index)) | Out-Null
    }
    if ($cursor -lt $text.Length) {
        $bad = $text.Substring($cursor)
        if ($bad.Trim().Length -gt 0) {
            Add-Finding $cursor 'ERROR' 'E004' 'Unterminated string literal at end of file'
        }
    }

    # --- structural walk ----------------------------------------------------
    $stack = [System.Collections.Generic.List[object]]::new()
    $ppStack = [System.Collections.Generic.List[object]]::new()
    $pairs = @{ '(' = ')'; '[' = ']'; '{' = '}' }
    $prev = $null          # previous significant token
    $condDepth = -1        # bracket depth at which an if/while condition started

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = $tokens[$i]

        if ($t.Kind -eq 'pp') {
            $directive = ([regex]::Match($t.Text, '^\#([A-Za-z_]+)')).Groups[1].Value.ToLowerInvariant()
            switch ($directive) {
                { $_ -in @('if', 'ifdef', 'ifndef') } { $ppStack.Add($t) | Out-Null }
                'endif' {
                    if ($ppStack.Count -eq 0) {
                        Add-Finding $t.Index 'ERROR' 'E005' '#endif without a matching #if/#ifdef/#ifndef'
                    } else { $ppStack.RemoveAt($ppStack.Count - 1) }
                }
            }
            $prev = $null   # a directive breaks statement adjacency
            continue
        }

        if ($t.Kind -eq 'br') {
            if ($pairs.ContainsKey($t.Text)) {
                # opening
                # Only a parenthesised condition - `waitUntil { _i = _i - 1; … }` and
                # `while {…}` bodies legitimately assign, so brace conditions are not tracked.
                if ($null -ne $prev -and $prev.Kind -eq 'id' -and
                    $script:ConditionKeywords.Contains($prev.Text) -and $t.Text -eq '(') {
                    $condDepth = $stack.Count
                }
                $stack.Add($t) | Out-Null
            } else {
                if ($stack.Count -eq 0) {
                    Add-Finding $t.Index 'ERROR' 'E003' ("Closing '{0}' with nothing open" -f $t.Text)
                } else {
                    $open = $stack[$stack.Count - 1]
                    $expected = $pairs[$open.Text]
                    if ($t.Text -ne $expected) {
                        $openPos = Get-LineCol $starts $open.Index
                        Add-Finding $t.Index 'ERROR' 'E001' ("Found '{0}' but '{1}' was expected (opened by '{2}' on line {3})" -f $t.Text, $expected, $open.Text, $openPos.Line)
                    }
                    $stack.RemoveAt($stack.Count - 1)
                    if ($stack.Count -le $condDepth) { $condDepth = -1 }
                }
            }
            $prev = $t
            continue
        }

        # inside which bracket are we right now?
        $scope = if ($stack.Count -gt 0) { $stack[$stack.Count - 1].Text } else { '' }

        if ($t.Kind -eq 'op') {
            switch ($t.Text) {
                ';' {
                    if ($scope -eq '[') {
                        Add-Finding $t.Index 'ERROR' 'E007' "';' inside an array literal - array elements are separated by ','"
                    }
                }
                ',' {
                    if ($scope -eq '{') {
                        Add-Finding $t.Index 'WARN' 'W002' "',' at code-block scope inside '{ }' - statements are separated by ';'"
                    }
                }
                '=' {
                    # Not inside a nested code block within the condition: `if (isNil { _v = … })`
                    # and similar are deliberate assignments, not a mistyped comparison.
                    $inNestedBlock = $false
                    if ($condDepth -ge 0) {
                        for ($s = $condDepth; $s -lt $stack.Count; $s++) {
                            if ($stack[$s].Text -eq '{') { $inNestedBlock = $true; break }
                        }
                    }
                    if (-not $inNestedBlock -and $condDepth -ge 0 -and $stack.Count -gt $condDepth) {
                        Add-Finding $t.Index 'WARN' 'W003' "Single '=' inside a condition - did you mean '=='  or 'isEqualTo'?"
                    }
                }
            }
        }

        if ($t.Kind -eq 'id' -and $t.Text -ieq 'else' -and $null -ne $prev -and $prev.Kind -eq 'op' -and $prev.Text -eq ';') {
            Add-Finding $t.Index 'ERROR' 'E006' "';' before 'else' ends the if-statement - remove it"
        }

        # missing semicolon after a code block
        if ($null -ne $prev -and $prev.Kind -eq 'br' -and $prev.Text -eq '}') {
            $starter = ($t.Kind -in @('id', 'num', 'dq', 'sq')) -or ($t.Kind -eq 'br' -and $t.Text -in @('(', '[', '{'))
            # A binary command continuing the same line (`… apply {…} createHashMapFromArray []`)
            # is normal SQF; a genuine missing ';' virtually always starts a new line.
            if ($starter -and $text.IndexOf("`n", $prev.Index, $t.Index - $prev.Index) -lt 0) { $starter = $false }
            if ($starter) {
                $ok = ($t.Kind -eq 'id' -and $script:AfterBlockOkSet.Contains($t.Text))
                # a macro invocation (ALL_CAPS or CamelCase macro) may expand to anything
                if (-not $ok -and $t.Kind -eq 'id' -and $t.Text -cmatch '^[A-Z][A-Za-z0-9_]*$' -and
                    $i + 1 -lt $tokens.Count -and $tokens[$i + 1].Kind -eq 'br' -and $tokens[$i + 1].Text -eq '(') { $ok = $true }
                if (-not $ok) {
                    Add-Finding $t.Index 'WARN' 'W001' ("Probable missing ';' after '}}' before '{0}'" -f $t.Text)
                }
            }
        }

        $prev = $t
    }

    foreach ($open in $stack) {
        Add-Finding $open.Index 'ERROR' 'E002' ("Unclosed '{0}' - no matching '{1}' before end of file" -f $open.Text, $pairs[$open.Text])
    }
    foreach ($open in $ppStack) {
        Add-Finding $open.Index 'ERROR' 'E005' 'Preprocessor conditional never closed with #endif'
    }

    # --- optional strict pass ----------------------------------------------
    if ($StrictMode) {
        $declared = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $declared.Add('_this') | Out-Null
        $declared.Add('_x') | Out-Null
        $declared.Add('_y') | Out-Null
        $declared.Add('_forEachIndex') | Out-Null
        $declared.Add('_exception') | Out-Null
        $declared.Add('_thisScript') | Out-Null
        $declared.Add('_thisArgs') | Out-Null
        $declared.Add('_thisEventHandler') | Out-Null
        $declared.Add('_fnc_scriptName') | Out-Null
        $declared.Add('_thisType') | Out-Null

        for ($i = 0; $i -lt $tokens.Count; $i++) {
            $t = $tokens[$i]
            if ($t.Kind -ne 'id') { continue }

            if ($script:DeclKeywords.Contains($t.Text)) {
                # private _a / private ["_a","_b"] / params ["_a", ...]
                for ($j = $i + 1; $j -lt $tokens.Count -and $j -lt $i + 60; $j++) {
                    $n = $tokens[$j]
                    if ($n.Kind -eq 'dq' -or $n.Kind -eq 'sq') {
                        $declared.Add($n.Text.Substring(1, $n.Text.Length - 2)) | Out-Null
                    } elseif ($n.Kind -eq 'id' -and $n.Text.StartsWith('_')) {
                        $declared.Add($n.Text) | Out-Null
                        if ($tokens[$i + 1].Kind -eq 'id') { break }
                    } elseif ($n.Kind -eq 'br' -and $n.Text -eq ']') {
                        break
                    } elseif ($n.Kind -eq 'op' -and $n.Text -eq ';') {
                        break
                    }
                }
                continue
            }
            if ($t.Text -ieq 'for' -or $t.Text -ieq 'foreach') {
                for ($j = $i + 1; $j -lt $tokens.Count -and $j -lt $i + 6; $j++) {
                    if ($tokens[$j].Kind -in @('dq', 'sq')) {
                        $declared.Add($tokens[$j].Text.Substring(1, $tokens[$j].Text.Length - 2)) | Out-Null
                    }
                }
                continue
            }
            if ($t.Text.StartsWith('_') -and $i + 1 -lt $tokens.Count) {
                $n = $tokens[$i + 1]
                if ($n.Kind -eq 'op' -and $n.Text -eq '=' -and -not $declared.Contains($t.Text)) {
                    Add-Finding $t.Index 'WARN' 'W004' ("Local '{0}' assigned without 'private' - it leaks into the caller's scope" -f $t.Text)
                    $declared.Add($t.Text) | Out-Null
                }
            }
        }
    }

    # Once the bracket stack is broken, every scope-sensitive finding after it is noise.
    if ($findings | Where-Object { $_.Code -in @('E001', 'E002', 'E003', 'E004') }) {
        $findings = [System.Collections.Generic.List[object]](
            @($findings | Where-Object { $_.Code -notin @('E007', 'W001', 'W002', 'W003', 'W004') }))
    }

    return $findings
}

# --------------------------------------------------------------- driver ----

function Resolve-TargetFiles {
    $files = [System.Collections.Generic.List[string]]::new()

    if ($Staged -or $PSBoundParameters.ContainsKey('Changed')) {
        Push-Location $script:RepoRoot
        try {
            if ($Staged) {
                $out = git diff --name-only --diff-filter=ACMR --cached
            } else {
                $ref = if ([string]::IsNullOrWhiteSpace($Changed)) { 'HEAD' } else { $Changed }
                $out = @(git diff --name-only --diff-filter=ACMR $ref) + @(git ls-files --others --exclude-standard)
            }
            foreach ($f in $out) {
                if ($f -and $f.EndsWith('.sqf', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $full = Join-Path $script:RepoRoot $f
                    if (Test-Path -LiteralPath $full) { $files.Add((Resolve-Path -LiteralPath $full).Path) | Out-Null }
                }
            }
        } finally { Pop-Location }
        return $files
    }

    $targets = if ($Path) { $Path } else { @($script:RepoRoot) }
    foreach ($p in $targets) {
        if (-not (Test-Path -LiteralPath $p)) {
            Write-Error "No such path: $p"
            exit 2
        }
        $item = Get-Item -LiteralPath $p
        if ($item.PSIsContainer) {
            Get-ChildItem -LiteralPath $p -Recurse -Filter *.sqf -File |
                Where-Object { $_.FullName -notmatch '\\(\.git|build|\.idea)\\' } |
                ForEach-Object { $files.Add($_.FullName) | Out-Null }
        } elseif ($item.Extension -ieq '.sqf') {
            $files.Add($item.FullName) | Out-Null
        }
    }
    return $files
}

function Get-BaselinePath {
    if ($Baseline) { return $Baseline }
    return (Join-Path $PSScriptRoot 'baseline.txt')
}

function Get-FindingKey($f) {
    return ('{0}|{1}|{2}' -f $f.File, $f.Code, $f.Source)
}

$targetFiles = @(Resolve-TargetFiles)
if ($targetFiles.Count -eq 0) {
    if (-not $Quiet) { Write-Host 'sqfcheck: no .sqf files to check.' }
    exit 0
}

$all = [System.Collections.Generic.List[object]]::new()
foreach ($file in $targetFiles) {
    foreach ($f in (Test-SqfFile $file ([bool]$Strict))) { $all.Add($f) | Out-Null }
}

$baselinePath = Get-BaselinePath
if ($UpdateBaseline) {
    $keys = $all | ForEach-Object { Get-FindingKey $_ } | Sort-Object -Unique
    Set-Content -LiteralPath $baselinePath -Value $keys -Encoding UTF8
    Write-Host ("sqfcheck: baseline written with {0} entries -> {1}" -f $keys.Count, $baselinePath)
    exit 0
}

$suppressed = 0
if (Test-Path -LiteralPath $baselinePath) {
    $known = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] (Get-Content -LiteralPath $baselinePath | Where-Object { $_ -and -not $_.StartsWith('#') }),
        [System.StringComparer]::Ordinal)
    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($f in $all) {
        if ($known.Contains((Get-FindingKey $f))) { $suppressed++ } else { $kept.Add($f) | Out-Null }
    }
    $all = $kept
}

$errors = @($all | Where-Object { $_.Level -eq 'ERROR' })
$warns = @($all | Where-Object { $_.Level -eq 'WARN' })

if ($Json) {
    $all | ConvertTo-Json -Depth 4
} else {
    foreach ($f in ($all | Sort-Object File, Line, Col)) {
        $colour = if ($f.Level -eq 'ERROR') { 'Red' } else { 'Yellow' }
        Write-Host ("{0}:{1}:{2}: {3} {4}: {5}" -f $f.File, $f.Line, $f.Col, $f.Level.ToLower(), $f.Code, $f.Message) -ForegroundColor $colour
        if ($f.Source) { Write-Host ("    | {0}" -f $f.Source) -ForegroundColor DarkGray }
    }
    if (-not $Quiet -or $all.Count -gt 0) {
        Write-Host ("sqfcheck: {0} file(s), {1} error(s), {2} warning(s){3}" -f `
            $targetFiles.Count, $errors.Count, $warns.Count, $(if ($suppressed) { ", $suppressed baselined" } else { '' }))
    }
}

if ($errors.Count -gt 0) { exit 1 }
if ($WarningsAsErrors -and $warns.Count -gt 0) { exit 1 }
exit 0
