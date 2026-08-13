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


