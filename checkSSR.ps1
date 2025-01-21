#!/usr/bin/env pwsh

Add-Type -AssemblyName System.Web

# Константы
$URLS_FILE = "urls.txt"
$OUTPUT_DIR = "responses"
$MAX_ATTEMPTS = 3
$RETRY_DELAY = 5

# Функции для цветного вывода
function Write-Red($message) { Write-Host $message -ForegroundColor Red }
function Write-Green($message) { Write-Host $message -ForegroundColor Green }
function Write-Yellow($message) { Write-Host $message -ForegroundColor Yellow }
function Write-Blue($message) { Write-Host $message -ForegroundColor Cyan }

# Проверка зависимостей
function Check-Dependencies {
    $dependencies = @("Invoke-WebRequest")
    foreach ($cmd in $dependencies) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            Write-Red "Ошибка: команда $cmd не найдена. Пожалуйста, убедитесь, что у вас установлен PowerShell 5.1 или выше."
            exit 1
        }
    }
}

# Проверка наличия файла urls.txt и его создание при отсутствии
function Check-UrlsFile {
    if (-not (Test-Path $URLS_FILE)) {
        "Добавьте один URL на строку вместо этого текста" | Out-File -FilePath $URLS_FILE -Encoding utf8
        Write-Yellow "Файл $URLS_FILE создан. Пожалуйста, заполните его ссылками для проверки."
        Write-Yellow "Каждая ссылка должна быть на отдельной строке."
        Write-Yellow "После заполнения файла запустите скрипт повторно."
        Write-Yellow "Нажмите Enter для выхода..."
        Read-Host
        exit 0
    }

    $content = Get-Content $URLS_FILE -Encoding utf8
    if ($content.Count -eq 0 -or -not ($content -match "^https?://")) {
        Write-Red "Файл $URLS_FILE пуст или не содержит допустимых URL."
        Write-Yellow "Пожалуйста, добавьте в файл $URLS_FILE ссылки для проверки."
        Write-Yellow "Каждая ссылка должна быть на отдельной строке и начинаться с http:// или https://"
        Write-Yellow "После заполнения файла запустите скрипт повторно."
        Write-Yellow "Нажмите Enter для выхода..."
        Read-Host
        exit 0
    }
}

# Вызов функций проверки
Check-Dependencies
Check-UrlsFile

# Создание директории для ответов
if (-not (Test-Path $OUTPUT_DIR)) {
    New-Item -ItemType Directory -Path $OUTPUT_DIR | Out-Null
}

# Определение User-Agent для ботов
$GOOGLE_UA = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
$YANDEX_UA = "Mozilla/5.0 (compatible; YandexBot/3.0; +http://yandex.com/bots)"

function Check-Url {
    param (
        [string]$url,
        [string]$ua,
        [string]$bot_name,
        [string]$output_file
    )

    for ($attempt = 1; $attempt -le $MAX_ATTEMPTS; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $url -UserAgent $ua -UseBasicParsing -ErrorAction Stop
            
            if ($response.StatusCode -eq 200) {
                $content = $response.Content
                if ($content) {
                    $content | Out-File -FilePath $output_file -Encoding utf8
                    Write-Green "Ответ успешно получен и сохранен (HTTP статус: $($response.StatusCode))"
                    return $true
                }
            }
            Write-Red "Получен некорректный ответ. HTTP статус: $($response.StatusCode)"
        }
        catch {
            Write-Red "Ошибка при выполнении запроса для $url"
        }

        if ($attempt -lt $MAX_ATTEMPTS) {
            Write-Host "Повторная попытка через $RETRY_DELAY секунд..."
            Start-Sleep -Seconds $RETRY_DELAY
        } else {
            Write-Red "Ошибка при получении $url с помощью $bot_name после $MAX_ATTEMPTS попыток"
            return $false
        }
    }
}

# Функция для получения чистого имени файла из URL
function Get-CleanFileName {
    param ([string]$url)
    $url -replace "^https?://", "" -replace "[^a-zA-Z0-9._-]", "_"
}

# Функция для проверки мета-тегов
function Check-MetaTags {
    param (
        [string]$content,
        [string]$url
    )

    # Проверка canonical
    $canonical = [regex]::Match($content, '<link[^>]*rel="canonical"[^>]*href="([^"]*)"[^>]*>').Groups[1].Value
    $canonical_correct = if ($canonical -eq $url) { "Верно" } else { "Неверно" }

    # Проверка description
    $description = [regex]::Match($content, '<meta[^>]*name="description"[^>]*content="([^"]*)"[^>]*>').Groups[1].Value
    $description_valid = if ($description) { "Присутствует" } else { "Отсутствует" }

    # Проверка title
    $title = [regex]::Match($content, '<title[^>]*>([^<]*)</title>').Groups[1].Value
    $title_valid = if ($title) { "Присутствует" } else { "Отсутствует" }

    # Проверка robots
    $robots = [regex]::Match($content, '<meta[^>]*name="robots"[^>]*content="([^"]*)"[^>]*>').Groups[1].Value
    if (-not $robots) { $robots = "Мета-тег не найден" }

    return @"
URL: $url
Canonical: $canonical_correct
Canonical_Value: $canonical
Description: $description_valid
Description_Value: $description
Title: $title_valid
Title_Value: $title
Robots: $robots
"@
}

# Функция для генерации HTML отчета
function Generate-HTMLReport {
    param (
        [string]$results,
        [string]$failed_urls,
        [int]$successful_checks,
        [int]$failed_checks
    )

    $total_checks = $successful_checks + $failed_checks
    $report_date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $html = @"
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Отчет о проверке мета-тегов</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { border-collapse: collapse; margin-bottom: 20px; }
        th, td { border: 1px solid #ddd; padding: 12px 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .success { color: green; }
        .error { color: red; }
        .details { font-size: 0.9em; color: #666; margin-top: 4px; }
        .google { color: #4285f4; }
        .яндекс { color: #ff4c00; }
        .noindex { font-weight: bold; color: orange; }
        .not-found { color: orange; }
        .report-info { width: auto; font-size: 0.9em; }
        .report-info th, .report-info td { padding: 3px 6px; }
        .successful-checks { color: green; }
        .failed-checks { color: red; }
    </style>
</head>
<body>
    <h1>Отчет о проверке мета-тегов</h1>
    <table class="report-info">
        <tr><th>Отчёт создан:</th><td>$report_date</td></tr>
        <tr><th>Всего проверено ссылок:</th><td>$total_checks</td></tr>
        <tr><th>Успешных проверок:</th><td class="successful-checks">$successful_checks</td></tr>
        <tr><th>Неудачных проверок:</th><td class="$(if ($failed_checks -gt 0) { 'failed-checks' })">$failed_checks</td></tr>
    </table>
    <h2>Успешные проверки</h2>
    <table>
        <tr>
            <th>URL</th>
            <th>Бот</th>
            <th>Canonical</th>
            <th>Title</th>
            <th>Description</th>
            <th>Robots</th>
        </tr>
"@

    $results -split "`n" | Where-Object { $_ -ne "" } | ForEach-Object {
        $fields = $_ -split "\|"
        $url, $bot, $canonical, $canonical_value, $title, $title_value, $description, $description_value, $robots = $fields
        $html += @"
        <tr>
            <td><a href="$([System.Web.HttpUtility]::HtmlEncode($url))" target="_blank">$([System.Web.HttpUtility]::HtmlEncode($url))</a></td>
            <td class="$($bot.ToLower())">$([System.Web.HttpUtility]::HtmlEncode($bot))</td>
            <td class="$(if ($canonical -eq "Верно") { "success" } else { "error" })">
                $([System.Web.HttpUtility]::HtmlEncode($canonical))<br>
                <span class="details">$([System.Web.HttpUtility]::HtmlEncode($canonical_value))</span>
            </td>
            <td class="$(if ($title -eq "Присутствует") { "success" } else { "error" })">
                $([System.Web.HttpUtility]::HtmlEncode($title))<br>
                <span class="details">$([System.Web.HttpUtility]::HtmlEncode($title_value))</span>
            </td>
            <td class="$(if ($description -eq "Присутствует") { "success" } else { "error" })">
                $([System.Web.HttpUtility]::HtmlEncode($description))<br>
                <span class="details">$([System.Web.HttpUtility]::HtmlEncode($description_value))</span>
            </td>
            <td>
                $(if ($robots -match "noindex") {
                    [System.Web.HttpUtility]::HtmlEncode($robots) -replace "noindex", '<span class="noindex">noindex</span>'
                } elseif ($robots -eq "Мета-тег не найден") {
                    '<span class="error">Мета-тег не найден</span>'
                } else {
                    [System.Web.HttpUtility]::HtmlEncode($robots)
                })
            </td>
        </tr>
"@
    }

    $html += "</table>"

    if ($failed_urls) {
        $html += @"
    <h2>Неудачные проверки</h2>
    <table>
        <tr>
            <th>URL</th>
            <th>Бот</th>
            <th>Причина</th>
        </tr>
"@
        $failed_urls -split "`n" | Where-Object { $_ -ne "" } | ForEach-Object {
            $fields = $_ -split "\|"
            $url, $bot, $reason = $fields
            $html += @"
        <tr>
            <td>$([System.Web.HttpUtility]::HtmlEncode($url))</td>
            <td class="$($bot.ToLower())">$([System.Web.HttpUtility]::HtmlEncode($bot))</td>
            <td class="error">$([System.Web.HttpUtility]::HtmlEncode($reason))</td>
        </tr>
"@
        }
        $html += "</table>"
    }

    $html += @"
</body>
</html>
"@

    return $html
}

# Основной скрипт
$successful_checks = 0
$failed_checks = 0
$results = ""
$failed_urls = ""

Get-Content $URLS_FILE -Encoding utf8 | Where-Object { $_ -match "^https?://" } | ForEach-Object {
    $url = $_

    @($GOOGLE_UA, $YANDEX_UA) | ForEach-Object {
        $ua = $_
        $bot = if ($ua -match "Googlebot") { "google" } else { "yandex" }
        $bot_name = if ($ua -match "Googlebot") { "Google" } else { "Яндекс" }
        $clean_filename = Get-CleanFileName $url
        $output_file = Join-Path $OUTPUT_DIR "${bot}_${clean_filename}.html"

        Write-Host "----------------------------------------"
        Write-Host "URL: " -ForegroundColor Yellow -NoNewline
        Write-Host $url -ForegroundColor Cyan
        Write-Host "Бот: " -ForegroundColor Yellow -NoNewline
        Write-Host $bot_name

        if (Test-Path $output_file) {
            Write-Host "Пропуск: " -ForegroundColor Cyan -NoNewline
            Write-Host "Файл уже существует" -ForegroundColor Cyan
            if (Test-Path $output_file -PathType Leaf) {
                $content = Get-Content $output_file -Raw -Encoding utf8
                $check_result = Check-MetaTags $content $url
                $success = $true
            } else {
                Write-Red "Ошибка: $output_file существует, но это не файл"
                $failed_urls += "$url|$bot|Ошибка: файл существует, но это не файл`n"
                $failed_checks++
                $success = $false
            }
        } else {
            Write-Yellow "Получение данных..."
            $success = Check-Url $url $ua $bot_name $output_file
            if ($success) {
                if (Test-Path $output_file -PathType Leaf) {
                    $content = Get-Content $output_file -Raw -Encoding utf8
                    $check_result = Check-MetaTags $content $url
                    Write-Yellow "Результаты проверки для URL: $(Write-Host $url -ForegroundColor Cyan)"
                    $check_result -split "`n" | ForEach-Object { Write-Host "  $_" }
                } else {
                    $success = $false
                }
            } else {
                $failed_urls += "$url|$bot|Ошибка при получении страницы`n"
                $failed_checks++
            }
        }

        if ($success) {
            # Обработка результатов проверки
            $canonical = ($check_result -split "`n" | Where-Object { $_ -match "^Canonical:" }) -replace "^Canonical:\s*", ""
            $canonical_value = ($check_result -split "`n" | Where-Object { $_ -match "^Canonical_Value:" }) -replace "^Canonical_Value:\s*", ""
            $title = ($check_result -split "`n" | Where-Object { $_ -match "^Title:" }) -replace "^Title:\s*", ""
            $title_value = ($check_result -split "`n" | Where-Object { $_ -match "^Title_Value:" }) -replace "^Title_Value:\s*", ""
            $description = ($check_result -split "`n" | Where-Object { $_ -match "^Description:" }) -replace "^Description:\s*", ""
            $description_value = ($check_result -split "`n" | Where-Object { $_ -match "^Description_Value:" }) -replace "^Description_Value:\s*", ""
            $robots = ($check_result -split "`n" | Where-Object { $_ -match "^Robots:" }) -replace "^Robots:\s*", ""

            $results += "$url|$bot_name|$canonical|$canonical_value|$title|$title_value|$description|$description_value|$robots`n"
            $successful_checks++
        }
    }
}

# Генерация и сохранение HTML отчета
$report_html = Generate-HTMLReport $results $failed_urls $successful_checks $failed_checks
$report_html | Out-File -FilePath (Join-Path $OUTPUT_DIR "combined_report.html") -Encoding utf8

Write-Green "====================================="
Write-Green " Все запросы завершены!"
Write-Host " "
Write-Yellow " Объединенный отчет сохранен в файл:"
Write-Blue " $(Join-Path (Get-Location) $OUTPUT_DIR 'combined_report.html')"
Write-Green "====================================="

if ($failed_urls) {
    Write-Red "==============================="
    Write-Red " ВНИМАНИЕ:"
    Write-Red " Обнаружены неудачные проверки!"
    Write-Red " Запустите скрипт ещё раз."
    Write-Red "==============================="
}

Write-Yellow "Нажмите Enter для выхода..."
Read-Host

