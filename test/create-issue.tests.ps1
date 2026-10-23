$script_directory = Split-Path -Parent $PSScriptRoot
$script_path = Join-Path $script_directory 'create-issue.ps1'
. $script_path

$UTF8_NO_BOM = [System.Text.UTF8Encoding]::new($false)
$OPENED_FORMAT = 'yyyy-MM-ddTHH:mm:ss.fffZ'
# Default template content from spec section 4, written independently of default-template.md.
$SPEC_DEFAULT = "---`nid: {{id}}`nopened: {{opened}}`nclosed:`ntitle:`n" +
    "status: open        # open | accepted | fixed | rejected | wontfix`n" +
    "fixed_in: []        # commit IDs, backfilled at version commit time`n" +
    "labels: []`nremote:`nproblem_title:`nproposal_title:`ndecision_title:`n---`n`n" +
"## Problem`n`n## Proposal`n`n## Decision`n"

$failures = 0
$checks = 0
function assert_true {
    param([bool]$condition, [string]$name)
    $script:checks++
    if (-not $condition) {
        [Console]::Out.WriteLine("FAIL $name")
        $script:failures++
    }
}
function assert_equal {
    param($actual, $expected, [string]$name)
    $script:checks++
    if ($actual -cne $expected) {
        [Console]::Out.WriteLine("FAIL ${name}: expected [$expected], got [$actual]")
        $script:failures++
    }
}
function assert_throws {
    param([scriptblock]$action, [string]$name)
    $thrown = $false
    try { & $action | Out-Null } catch { $thrown = $true }
    assert_true $thrown $name
}

function quote_argument {
    param([string]$text)
    return '"' + $text.Replace('\', '\\').Replace('"', '\"') + '"'
}

# Runs the script in a child process; returns exit code, stdout and stderr.
function invoke_child {
    param([string]$executable, [string]$working_directory, [string[]]$arguments)

    $start_info = New-Object System.Diagnostics.ProcessStartInfo
    $start_info.FileName = $executable
    $quoted = @('-NoProfile', '-NonInteractive', '-File', (quote_argument $script_path))
    foreach ($argument in $arguments) { $quoted += quote_argument $argument }
    $start_info.Arguments = $quoted -join ' '
    $start_info.WorkingDirectory = $working_directory
    $start_info.UseShellExecute = $false
    $start_info.RedirectStandardOutput = $true
    $start_info.RedirectStandardError = $true
    $start_info.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($start_info)
    $stderr_task = $process.StandardError.ReadToEndAsync()
    $stdout = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{ exit_code = $process.ExitCode; stdout = $stdout; stderr = $stderr_task.Result }
}

function new_project_directory {
    $path = Join-Path $script:temporary_root ([guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($path)
    return $path
}

function read_front_matter_value {
    param([string]$content, [string]$key)
    $match = [regex]::Match($content, "(?m)^${key}: (\S+)$")
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function get_id_from_opened {
    param([string]$opened)
    $parsed = [datetimeoffset]::ParseExact($opened, $OPENED_FORMAT, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
    return get_issue_id $parsed.ToUnixTimeMilliseconds()
}

function test_clean_bytes {
    param([byte[]]$bytes)
    $has_bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    return (-not $has_bom) -and (-not ($bytes -contains 0x0D))
}

function get_directory_listing {
    param([string]$path)
    return (@([System.IO.Directory]::GetFileSystemEntries($path) | Sort-Object) -join '|')
}

# 1. id vectors
$id_vectors = @(
    @(0, 'bzpepsqz'), @(1, 'de3b4wzz'), @(1792281811121, 'ggkpa773'),
    @(1792281811122, 'kymnq2en'), @(1792281811123, 'ae16cpvt'),
    @(1792281812121, 'm5s8m0xw'), @(1792281871121, '3q0vprjn')
)
foreach ($vector in $id_vectors) {
    assert_equal (get_issue_id $vector[0]) $vector[1] "id $($vector[0])"
}

# 2. slugs and dates at function level
$slug_60 = 'a' * 60
$slug_61 = 'a' * 61
$slug_non_ascii = 'fix' + [char]0x00E9
$valid_slugs = @('a', 'fix-bug', 'x2', '20261018', $slug_60)
$invalid_slugs = @('', 'Fix-Bug', 'fix_bug', 'fix bug', '-fix', 'fix-', 'fix--bug', $slug_non_ascii, $slug_61, "fix`n")
foreach ($slug in $valid_slugs) { assert_true (test_slug $slug) "valid slug [$slug]" }
foreach ($slug in $invalid_slugs) { assert_true (-not (test_slug $slug)) "invalid slug [$slug]" }

$date_vectors = @(
    @('20261018', '2026-10-18T00:00:00.000Z', 'jazq3ynk'),
    @('202610180823', '2026-10-18T08:23:00.000Z', 'mz0rpmrq'),
    @('20261018082311', '2026-10-18T08:23:11.000Z', 'amck341k'),
    @('20261018082311121', '2026-10-18T08:23:11.121Z', 'tv5eqvx6'),
    @('20240229', '2024-02-29T00:00:00.000Z', '85gyraxj'),
    @('19700101', '1970-01-01T00:00:00.000Z', 'bzpepsqz')
)
foreach ($vector in $date_vectors) {
    $epoch_ms = parse_date_argument $vector[0]
    assert_equal (format_opened $epoch_ms) $vector[1] "opened $($vector[0])"
    assert_equal (get_issue_id $epoch_ms) $vector[2] "date id $($vector[0])"
}
$invalid_dates = @('2026101', '2026101808231', '20251301', '20250230', '20261018240000', 'abc', '20261018x', '2026-10-18', '', '19691231', "2026101`n")
foreach ($invalid in $invalid_dates) {
    assert_throws { parse_date_argument $invalid } "invalid date [$invalid]"
}

$executables = @('pwsh')
if (Get-Command powershell -ErrorAction SilentlyContinue) { $executables += 'powershell' }
else { [Console]::Out.WriteLine('NOTE powershell (5.1) not found; child tests run under pwsh only') }

$script_directory_before = get_directory_listing $script_directory
$original_location = Get-Location
$temporary_root = Join-Path ([System.IO.Path]::GetTempPath()) ('create-issue-tests-' + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($temporary_root)
try {
    foreach ($executable in $executables) {
        # 2. usage errors through a child process
        $usage_cases = @(@(), @(, ''))
        foreach ($slug in $invalid_slugs) { if ($slug -ne '') { $usage_cases += , @(, $slug) } }
        foreach ($invalid in $invalid_dates) { $usage_cases += , @('fix-bug', $invalid) }
        $usage_cases += , @('fix-bug', '20261018', 'extra')
        foreach ($case in $usage_cases) {
            $project = new_project_directory
            $run = invoke_child $executable $project $case
            $label = "$executable usage [$($case -join '] [')]"
            assert_equal $run.exit_code 2 "$label exit code"
            assert_equal $run.stdout '' "$label stdout empty"
            assert_true ($run.stderr.Trim().Length -gt 0 -and $run.stderr.Trim() -notmatch "`n") "$label one-line stderr"
            assert_true (-not [System.IO.Directory]::Exists((Join-Path $project 'issues'))) "$label no issues directory"
        }

        # 3. end to end with an explicit date; 8. unrelated file untouched
        $project = new_project_directory
        $unrelated_path = Join-Path $project 'README.md'
        [System.IO.File]::WriteAllText($unrelated_path, "keep`r`nme", $UTF8_NO_BOM)
        $unrelated_before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($unrelated_path))
        $run = invoke_child $executable $project @('fix-bug', '20261018082311121')
        assert_equal $run.exit_code 0 "$executable e2e exit code"
        assert_equal $run.stdout "tv5eqvx6-fix-bug.md$([Environment]::NewLine)" "$executable e2e stdout"
        $issue_files = @([System.IO.Directory]::GetFiles((Join-Path $project 'issues')))
        assert_equal $issue_files.Count 1 "$executable e2e one file"
        $issue_path = Join-Path $project 'issues/tv5eqvx6-fix-bug.md'
        assert_true ([System.IO.File]::Exists($issue_path)) "$executable e2e file name"
        if ([System.IO.File]::Exists($issue_path)) {
            $bytes = [System.IO.File]::ReadAllBytes($issue_path)
            $content = $UTF8_NO_BOM.GetString($bytes)
            $id = read_front_matter_value $content 'id'
            $opened = read_front_matter_value $content 'opened'
            assert_equal $id 'tv5eqvx6' "$executable e2e id equals file prefix"
            assert_equal $opened '2026-10-18T08:23:11.121Z' "$executable e2e opened"
            assert_equal (get_id_from_opened $opened) $id "$executable e2e id derivable from opened"
            assert_true ($content -cmatch '(?m)^status: open\b') "$executable e2e status open"
            foreach ($heading in @($SPEC_DEFAULT -split "`n" | Where-Object { $_.StartsWith('## ') })) {
                assert_true ($content.Contains("`n$heading`n")) "$executable e2e heading present"
            }
            assert_true (-not $content.Contains('fix-bug')) "$executable e2e slug not in content"
            assert_true (test_clean_bytes $bytes) "$executable e2e no bom and no cr"
        }

        # 4. same explicit date twice with different slugs
        $first_before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($issue_path))
        $run = invoke_child $executable $project @('other-bug', '20261018082311121')
        assert_equal $run.exit_code 1 "$executable collision exit code"
        assert_equal $run.stdout '' "$executable collision stdout empty"
        assert_true ($run.stderr.Contains('tv5eqvx6-fix-bug.md')) "$executable collision names existing file"
        assert_equal @([System.IO.Directory]::GetFiles((Join-Path $project 'issues'))).Count 1 "$executable collision creates nothing"
        assert_equal ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($issue_path))) $first_before "$executable collision keeps first file"
        assert_equal ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($unrelated_path))) $unrelated_before "$executable unrelated file unchanged"

        # 5. no date argument
        $project = new_project_directory
        $before_ms = [datetimeoffset]::UtcNow.ToUnixTimeMilliseconds()
        $run = invoke_child $executable $project @('now-bug')
        $after_ms = [datetimeoffset]::UtcNow.ToUnixTimeMilliseconds()
        assert_equal $run.exit_code 0 "$executable now exit code"
        $file_name = $run.stdout.Trim()
        assert_true ($file_name -cmatch '^[0-9a-z]{8}-now-bug\.md$') "$executable now file name [$file_name]"
        $now_path = Join-Path $project "issues/$file_name"
        if ($file_name -ne '' -and [System.IO.File]::Exists($now_path)) {
            $content = [System.IO.File]::ReadAllText($now_path, [System.Text.Encoding]::UTF8)
            $opened = read_front_matter_value $content 'opened'
            $opened_ms = [datetimeoffset]::ParseExact($opened, $OPENED_FORMAT, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).ToUnixTimeMilliseconds()
            assert_true ($opened_ms -ge $before_ms - 5000 -and $opened_ms -le $after_ms + 5000) "$executable now opened within 5 seconds"
            assert_equal (get_id_from_opened $opened) $file_name.Substring(0, 8) "$executable now id matches opened"
        }
        else {
            assert_true $false "$executable now file exists"
        }
    }

    # 6. bump rule at function level
    $project = new_project_directory
    Set-Location -LiteralPath $project
    $bump_ms = 1792281811121
    $first_id = get_issue_id $bump_ms
    [void][System.IO.Directory]::CreateDirectory((Join-Path $project 'issues'))
    $other_path = Join-Path $project "issues/$first_id-other.md"
    [System.IO.File]::WriteAllText($other_path, 'original', $UTF8_NO_BOM)
    $bumped = create_issue_file 'new-slug' $bump_ms $true
    assert_equal $bumped.epoch_ms ($bump_ms + 1) 'bump millisecond'
    assert_equal $bumped.file_name "$(get_issue_id ($bump_ms + 1))-new-slug.md" 'bump file name'
    assert_equal ([System.IO.File]::ReadAllText($other_path)) 'original' 'bump preserves original'
    assert_throws { create_issue_file 'new-slug-2' $bump_ms $false } 'no bump fails on collision'
    [System.IO.File]::WriteAllText((Join-Path $project 'issues/jazq3ynk.md'), 'bare', $UTF8_NO_BOM)
    assert_throws { create_issue_file 'any' (parse_date_argument '20261018') $false } 'bare id file name counts as collision'

    # 9. template selection
    $project = new_project_directory
    Set-Location -LiteralPath $project
    $default_issue = create_issue_file 'default-template' 1792281812121 $false
    $expected_default = $SPEC_DEFAULT.Replace('{{id}}', 'm5s8m0xw').Replace('{{opened}}', '2026-10-18T00:03:32.121Z')
    assert_equal ([System.IO.File]::ReadAllText($default_issue.file_path, [System.Text.Encoding]::UTF8)) $expected_default 'built-in default template'
    assert_equal (get_template (Join-Path $project 'issues')) $SPEC_DEFAULT 'default template matches spec'

    $custom_text = 'custom ' + (-join [char[]]@(0x6A21, 0x677F)) + "`r`nid={{id}}`r`nopened={{opened}}`r`n"
    $template_path = Join-Path $project 'issues/template.md'
    [System.IO.File]::WriteAllText($template_path, $custom_text, $UTF8_NO_BOM)
    $template_before = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($template_path))
    $custom_issue = create_issue_file 'custom-template' 1792281871121 $false
    $custom_bytes = [System.IO.File]::ReadAllBytes($custom_issue.file_path)
    $expected_custom = $custom_text.Replace("`r`n", "`n").Replace('{{id}}', '3q0vprjn').Replace('{{opened}}', '2026-10-18T00:04:31.121Z')
    assert_equal $UTF8_NO_BOM.GetString($custom_bytes) $expected_custom 'project template used'
    assert_true (test_clean_bytes $custom_bytes) 'project template output no bom and no cr'
    assert_equal ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($template_path))) $template_before 'template unchanged'

    # 9. opened is filled even when the template does not write {{opened}}
    $opened_cases = @(
        @('empty value', "---`r`nid: {{id}}`r`nopened:`r`n---`r`nbody opened: keep`r`nopened:`r`n", 1792281811122,
            "---`nid: kymnq2en`nopened: 2026-10-18T00:03:31.122Z`n---`nbody opened: keep`nopened:`n"),
        @('other value with comment', "---`nopened: 2000-01-01   # filled by create-issue`ntitle:`n---`n", 1792281811123,
            "---`nopened: 2026-10-18T00:03:31.123Z   # filled by create-issue`ntitle:`n---`n")
    )
    foreach ($case in $opened_cases) {
        [System.IO.File]::WriteAllText($template_path, $case[1], $UTF8_NO_BOM)
        $opened_issue = create_issue_file 'opened-field' $case[2] $false
        assert_equal ([System.IO.File]::ReadAllText($opened_issue.file_path, [System.Text.Encoding]::UTF8)) $case[3] "template opened $($case[0])"
    }
    assert_equal (set_front_matter_value "---`ntitle:`n---`nopened:`n" 'opened' 'T') "---`ntitle:`n---`nopened:`n" 'no opened line added'
    assert_equal (set_front_matter_value "text`n---`nopened:`n---`n" 'opened' 'T') "text`n---`nopened:`n---`n" 'no front matter untouched'
    assert_equal (set_front_matter_value "---`nopened: {{opened}}`nopened: x`n---" 'opened' 'T') "---`nopened: T`nopened: x`n---" 'only first opened line set'

    # 9. closed is always cleared
    [System.IO.File]::WriteAllText($template_path, "---`nopened:`nclosed: 2000-01-01T00:00:00.000Z   # set on close`n---`nclosed: keep`n", $UTF8_NO_BOM)
    $closed_issue = create_issue_file 'closed-field' 1792281811121 $false
    assert_equal ([System.IO.File]::ReadAllText($closed_issue.file_path, [System.Text.Encoding]::UTF8)) "---`nopened: 2026-10-18T00:03:31.121Z`nclosed:   # set on close`n---`nclosed: keep`n" 'template closed cleared'
    assert_equal (set_front_matter_value "---`ntitle:`n---`n" 'closed' '') "---`ntitle:`n---`n" 'no closed line added'

    # 9. default template missing next to the script
    $lone_directory = new_project_directory
    [System.IO.File]::Copy($script_path, (Join-Path $lone_directory 'create-issue.ps1'))
    $lone_script = Join-Path $lone_directory 'create-issue.ps1'
    foreach ($executable in $executables) {
        $project = new_project_directory
        $saved_script_path = $script_path
        $script_path = $lone_script
        $run = invoke_child $executable $project @('lone-script', '20261018')
        assert_equal $run.exit_code 1 "$executable missing default template exit code"
        assert_true ($run.stderr.Contains($DEFAULT_TEMPLATE_FILE_NAME)) "$executable missing default template named in stderr"
        assert_true (-not [System.IO.Directory]::Exists((Join-Path $project 'issues'))) "$executable missing default template creates nothing"

        [void][System.IO.Directory]::CreateDirectory((Join-Path $project 'issues'))
        [System.IO.File]::WriteAllText((Join-Path $project 'issues/template.md'), "id: {{id}}`n", $UTF8_NO_BOM)
        $run = invoke_child $executable $project @('lone-script', '20261018')
        $script_path = $saved_script_path
        assert_equal $run.exit_code 0 "$executable project template without default template"
    }
}
finally {
    Set-Location -LiteralPath $original_location.Path
    if ([System.IO.Directory]::Exists($temporary_root)) { Remove-Item -LiteralPath $temporary_root -Recurse -Force }
}

assert_equal (get_directory_listing $script_directory) $script_directory_before 'script directory unchanged'

# 7. script files are ASCII only, no BOM, no CR
foreach ($path in @($script_path, $PSCommandPath)) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    assert_true (test_clean_bytes $bytes) "$(Split-Path -Leaf $path) no bom and no cr"
    assert_true (-not ($bytes | Where-Object { $_ -gt 127 })) "$(Split-Path -Leaf $path) ascii only"
}
$default_template_bytes = [System.IO.File]::ReadAllBytes((Join-Path (Join-Path $script_directory 'src') $DEFAULT_TEMPLATE_FILE_NAME))
assert_true (test_clean_bytes $default_template_bytes) "$DEFAULT_TEMPLATE_FILE_NAME no bom and no cr"

if ($failures -eq 0) {
    [Console]::Out.WriteLine("PASS $checks checks")
    exit 0
}
[Console]::Out.WriteLine("FAILED $failures of $checks checks")
exit 1
