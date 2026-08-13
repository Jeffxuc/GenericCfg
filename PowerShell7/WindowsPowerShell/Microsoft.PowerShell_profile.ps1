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