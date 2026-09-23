function proxy-on {
  $env:HTTP_PROXY  = "http://127.0.0.1:7890"
  $env:HTTPS_PROXY = "http://127.0.0.1:7890"
  proxy-show
}

function proxy-off {
  Remove-Item Env:HTTP_PROXY
  Remove-Item Env:HTTPS_PROXY
  proxy-show
}

function proxy-show {
  Write-Host "HTTP_PROXY  =" $env:HTTP_PROXY
  Write-Host "HTTPS_PROXY =" $env:HTTPS_PROXY
}

function actenv {
    if (Test-Path ".\.venv\Scripts\Activate.ps1") {
        & ".\.venv\Scripts\Activate.ps1"
    } else {
        Write-Host "can't find virtual python environment" -ForegroundColor Yellow
    }
}


# 1. 关键：禁止虚拟环境脚本自动修改 Prompt 布局
# 这样虚拟环境名称就不会被乱放，而是由我们接管显示位置
$env:VIRTUAL_ENV_DISABLE_PROMPT = 1

function prompt {
    # --- A. 获取虚拟环境名称 ---
    $venvName = ""
    if ($env:VIRTUAL_ENV) {
        # 取路径的最后一个文件夹名，例如 D:\...\orca -> orca
        $venvName = "(" + (Split-Path $env:VIRTUAL_ENV -Leaf) + ")"
    } elseif ($env:CONDA_DEFAULT_ENV) {
        # 如果你后续使用 Conda，这行也管用
        $venvName = "(" + $env:CONDA_DEFAULT_ENV + ")"
    }

    # --- B. 获取路径和 Git 信息 ---
    $currentPath = $ExecutionContext.SessionState.Path.CurrentLocation
    $gitBranch = git rev-parse --abbrev-ref HEAD 2>$null

    # --- C. 开始按顺序绘制 ---
    
    # 换行，让输出更有呼吸感
    Write-Host "`n" -NoNewline

    # 1. 如果有虚拟环境，显示在最前面（绿色高亮）
    if ($venvName) {
        Write-Host "$venvName " -NoNewline -ForegroundColor Green
    }

    # 2. 显示 "PS " 和当前路径
    Write-Host "PS " -NoNewline -ForegroundColor White
    Write-Host "$currentPath" -NoNewline -ForegroundColor Cyan
    
    # 3. 显示 Git 分支
    if ($null -ne $gitBranch) {
        Write-Host " [" -NoNewline -ForegroundColor Gray
        Write-Host "$gitBranch" -NoNewline -ForegroundColor Yellow
        Write-Host "]" -NoNewline -ForegroundColor Gray
    }

    # 4. 最后换行并显示输入符
    return "`n> "
}

# 设置自动补全快捷键，默认右方向键补全整行，现在设置 "ctrl + 右方向键" 只补全下一个单词
Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function AcceptNextSuggestionWord

function tree-cn {
    $old = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(936)
    & tree.exe @args
    [Console]::OutputEncoding = $old
}

# 获取指定路径下的目录大小，默认当前目录，可自行指定目录，-Top 10 只显示前10个
function getDirSize {
    param(
        [Parameter(Position = 0)]
        [string]$Path = ".",

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Top = 0
    )

    # 获取绝对路径
    try {
        $root = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    }
    catch {
        Write-Error "路径不存在或无法访问: $Path"
        return
    }

    # 获取当前目录第一层目录
    $topDirs = Get-ChildItem `
        -LiteralPath $root `
        -Directory `
        -Force `
        -ErrorAction SilentlyContinue

    if (-not $topDirs) {
        Write-Host "当前目录没有子目录: $root"
        return
    }

    # 初始化每个第一层目录的大小
    $sizes = @{}

    foreach ($dir in $topDirs) {
        $sizes[$dir.Name] = [int64]0
    }

    # 整个目录树只递归扫描一次
    Get-ChildItem `
        -LiteralPath $root `
        -File `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue |
    ForEach-Object {

        # 获取相对于根目录的路径
        $relativePath = [System.IO.Path]::GetRelativePath(
            $root,
            $_.FullName
        )

        # Windows 路径分隔符
        $separator = [System.IO.Path]::DirectorySeparatorChar

        # 获取第一层目录名称
        $parts = $relativePath.Split($separator, 2)

        if ($parts.Count -ge 2) {
            $topDirName = $parts[0]

            if ($sizes.ContainsKey($topDirName)) {
                $sizes[$topDirName] += $_.Length
            }
        }
    }

    # 生成结果
    $result = foreach ($dir in $topDirs) {

        $size = $sizes[$dir.Name]

        # 自动选择合适的单位
        if ($size -ge 1TB) {
            $displaySize = "{0:N2} TB" -f ($size / 1TB)
        }
        elseif ($size -ge 1GB) {
            $displaySize = "{0:N2} GB" -f ($size / 1GB)
        }
        elseif ($size -ge 1MB) {
            $displaySize = "{0:N2} MB" -f ($size / 1MB)
        }
        elseif ($size -ge 1KB) {
            $displaySize = "{0:N2} KB" -f ($size / 1KB)
        }
        else {
            $displaySize = "{0:N0} B" -f $size
        }

        [PSCustomObject]@{
            Name      = $dir.Name
            Size      = $displaySize
            SizeBytes = $size
        }
    }

    # 按实际字节数从大到小排序
    $result = $result |
        Sort-Object SizeBytes -Descending

    # -Top 大于 0 时，只取前 N 个
    if ($Top -gt 0) {
        $result = $result | Select-Object -First $Top
    }

    # 输出结果
    $result |
        Format-Table Name, Size -AutoSize
}


