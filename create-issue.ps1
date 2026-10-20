$BASE32_ALPHABET = '0123456789abcdefghjkmnpqrstvwxyz'
$SLUG_PATTERN = '^[a-z0-9]+(-[a-z0-9]+)*\z'
$SLUG_MAX_LENGTH = 60
$MAX_BUMP_ATTEMPTS = 1000
$TEMPLATE_FILE_NAME = 'template.md'
$DEFAULT_TEMPLATE_FILE_NAME = 'default-template.md'
$USAGE = 'usage: create-issue <slug> [date]'

# Returns the project template ./issues/template.md, or else the default template
# next to this script; both are read as UTF-8 and normalized to LF.
function get_template {
    param([string]$issues_directory)

    $template_path = [System.IO.Path]::Combine($issues_directory, $TEMPLATE_FILE_NAME)
    if (-not [System.IO.File]::Exists($template_path)) {
        $template_path = [System.IO.Path]::Combine($PSScriptRoot, 'src', $DEFAULT_TEMPLATE_FILE_NAME)
        if (-not [System.IO.File]::Exists($template_path)) {
            throw [System.IO.FileNotFoundException]::new("default template not found: $template_path")
        }
    }
    $template = [System.IO.File]::ReadAllText($template_path, [System.Text.Encoding]::UTF8)
    return $template.Replace("`r`n", "`n").Replace("`r", "`n")
}

function test_slug {
    param([string]$slug)

    if ([string]::IsNullOrEmpty($slug) -or $slug.Length -gt $SLUG_MAX_LENGTH) {
        return $false
    }
    return [bool]($slug -cmatch $SLUG_PATTERN)
}

function parse_date_argument {
    param([string]$date_text)

    if ([string]::IsNullOrEmpty($date_text) -or $date_text -cnotmatch '^[0-9]+\z' -or $date_text.Length -notin @(8, 12, 14, 17)) {
        throw [System.ArgumentException]::new('date must be 8, 12, 14, or 17 digits')
    }

    $year = [int]$date_text.Substring(0, 4)
    $month = [int]$date_text.Substring(4, 2)
    $day = [int]$date_text.Substring(6, 2)
    $hour = if ($date_text.Length -ge 12) { [int]$date_text.Substring(8, 2) } else { 0 }
    $minute = if ($date_text.Length -ge 12) { [int]$date_text.Substring(10, 2) } else { 0 }
    $second = if ($date_text.Length -ge 14) { [int]$date_text.Substring(12, 2) } else { 0 }
    $millisecond = if ($date_text.Length -eq 17) { [int]$date_text.Substring(14, 3) } else { 0 }

    if ($year -lt 1970) {
        throw [System.ArgumentException]::new('date must not be before 1970')
    }

    try {
        $date_time = [datetime]::new($year, $month, $day, $hour, $minute, $second, $millisecond, [System.DateTimeKind]::Utc)
    }
    catch {
        throw [System.ArgumentException]::new('date is not a valid UTC calendar time')
    }
    return ([datetimeoffset]$date_time).ToUnixTimeMilliseconds()
}

function get_issue_id {
    param([Int64]$epoch_ms)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($epoch_ms.ToString([Globalization.CultureInfo]::InvariantCulture))
        $digest = $sha256.ComputeHash($bytes)
    }
    finally {
        $sha256.Dispose()
    }

    [UInt64]$value = 0
    for ($index = 0; $index -lt 5; $index++) {
        $value = ($value -shl 8) -bor [UInt64]$digest[$index]
    }

    $characters = New-Object char[] 8
    for ($index = 7; $index -ge 0; $index--) {
        $characters[$index] = $BASE32_ALPHABET[[int]($value -band 31)]
        $value = $value -shr 5
    }
    return -join $characters
}

function format_opened {
    param([Int64]$epoch_ms)

    return [datetimeoffset]::FromUnixTimeMilliseconds($epoch_ms).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture)
}

# Sets the first `opened:` line of the leading front matter to $opened, keeping a trailing comment.
function set_front_matter_opened {
    param([string]$content, [string]$opened)

    $front_matter = [regex]::Match($content, '\A---\n(?:.*\n)*?---(?:\n|\z)')
    if (-not $front_matter.Success) {
        return $content
    }
    $opened_line = [regex]::Match($front_matter.Value, '(?m)^opened:(?<value>.*?)(?<comment>[ \t]+#.*)?$')
    if (-not $opened_line.Success) {
        return $content
    }
    $new_line = "opened: $opened" + $opened_line.Groups['comment'].Value
    return $content.Substring(0, $opened_line.Index) + $new_line + $content.Substring($opened_line.Index + $opened_line.Length)
}

# Returns the name of an existing issue file that uses $id, or $null.
function find_issue_by_id {
    param([string]$issues_directory, [string]$id)

    if (-not [System.IO.Directory]::Exists($issues_directory)) {
        return $null
    }
    $ignore_case = [System.StringComparison]::OrdinalIgnoreCase
    foreach ($file_path in [System.IO.Directory]::GetFiles($issues_directory)) {
        $name = [System.IO.Path]::GetFileName($file_path)
        if ($name.Equals($TEMPLATE_FILE_NAME, $ignore_case)) {
            continue
        }
        if ($name.Equals("$id.md", $ignore_case) -or ($name.StartsWith("$id-", $ignore_case) -and $name.EndsWith('.md', $ignore_case))) {
            return $name
        }
    }
    return $null
}

function create_issue_file {
    param(
        [string]$slug,
        [Int64]$opened_ms,
        [bool]$bump_allowed
    )

    if (-not (test_slug $slug)) {
        throw [System.ArgumentException]::new("invalid slug: $slug")
    }

    $issues_directory = [System.IO.Path]::Combine((Get-Location -PSProvider FileSystem).ProviderPath, 'issues')
    $template = get_template $issues_directory
    [void][System.IO.Directory]::CreateDirectory($issues_directory)

    $attempts = if ($bump_allowed) { $MAX_BUMP_ATTEMPTS } else { 1 }
    for ($attempt = 0; $attempt -lt $attempts; $attempt++) {
        $candidate_ms = $opened_ms + $attempt
        $id = get_issue_id $candidate_ms
        $existing_name = find_issue_by_id $issues_directory $id
        if ($null -ne $existing_name) {
            if (-not $bump_allowed) {
                throw [System.IO.IOException]::new("issue id $id already used by: $existing_name")
            }
            continue
        }

        $opened = format_opened $candidate_ms
        $file_name = "$id-$slug.md"
        $file_path = [System.IO.Path]::Combine($issues_directory, $file_name)
        $content = set_front_matter_opened ($template.Replace('{{id}}', $id).Replace('{{opened}}', $opened)) $opened
        $content_bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($content)

        try {
            $stream = [System.IO.File]::Open($file_path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        }
        catch [System.IO.IOException] {
            if (-not [System.IO.File]::Exists($file_path)) {
                throw
            }
            if (-not $bump_allowed) {
                throw [System.IO.IOException]::new("issue id $id already used by: $file_name")
            }
            continue
        }
        try {
            $stream.Write($content_bytes, 0, $content_bytes.Length)
        }
        finally {
            $stream.Dispose()
        }
        return [pscustomobject]@{ file_name = $file_name; file_path = $file_path; id = $id; opened = $opened; epoch_ms = $candidate_ms }
    }

    throw [System.IO.IOException]::new("could not find a free issue id after $MAX_BUMP_ATTEMPTS attempts")
}

function write_stderr {
    param([string]$message)
    [Console]::Error.WriteLine($message)
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($args.Count -lt 1 -or $args.Count -gt 2) {
        write_stderr "$USAGE (expected 1 or 2 arguments, got $($args.Count))"
        exit 2
    }

    $slug = [string]$args[0]
    if (-not (test_slug $slug)) {
        write_stderr "$USAGE (invalid slug; must match $SLUG_PATTERN, at most $SLUG_MAX_LENGTH characters)"
        exit 2
    }

    if ($args.Count -eq 2) {
        try {
            $opened_ms = parse_date_argument ([string]$args[1])
        }
        catch {
            write_stderr "$USAGE ($($_.Exception.Message))"
            exit 2
        }
        $bump_allowed = $false
    }
    else {
        $opened_ms = [datetimeoffset]::UtcNow.ToUnixTimeMilliseconds()
        $bump_allowed = $true
    }

    try {
        $result = create_issue_file $slug $opened_ms $bump_allowed
    }
    catch {
        write_stderr $_.Exception.Message
        exit 1
    }
    [Console]::Out.WriteLine($result.file_name)
    exit 0
}
