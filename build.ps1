# Uso:  .\build.ps1 image | fetch | configure | compile | package | all | shell
param([Parameter(Mandatory=$true)][string]$Task)
$ErrorActionPreference = "Continue"   # stderr de docker no debe cortar el script
New-Item -ItemType Directory -Force -Path out | Out-Null
# Volumen con nombre para fuentes y build (el bind mount de Windows es muy lento)
$run = @("run","--rm","-v","mkxpz-work:/work","-v","${PWD}/out:/out","-v","${PWD}:/kit:ro","trimui-mkxpz")
# build.sh se copia sin CRLF por si Windows lo convirtio
$fix = "tr -d '\r' < /kit/build.sh > /tmp/build.sh && tr -d '\r' < /kit/cross-aarch64.txt > /tmp/cross.txt && sed -i 's#/kit/cross-aarch64.txt#/tmp/cross.txt#' /tmp/build.sh && bash /tmp/build.sh"
switch ($Task) {
  "image" { docker build -t trimui-mkxpz . }
  "shell" { docker run --rm -it -v mkxpz-work:/work -v "${PWD}/out:/out" -v "${PWD}:/kit:ro" trimui-mkxpz bash }
  default {
    # Guarda el log y muestra el final (pega aqui las ultimas 30 lineas si falla)
    # stderr se mezcla con stdout DENTRO del contenedor (si no, PowerShell lo toma por error)
    docker @run bash -c "( $fix $Task ) 2>&1" | Tee-Object -FilePath "out/build-$Task.log"
    $code = $LASTEXITCODE
    Write-Host "`n--- ultimas 30 lineas ---"; Get-Content "out/build-$Task.log" -Tail 30
    if ($code -ne 0) { Write-Host "`nFALLO (codigo $code). Pega las lineas que empiezan por 'error' y las 2-3 anteriores." -ForegroundColor Red }
    else { Write-Host "`nOK: etapa '$Task' terminada." -ForegroundColor Green }
  }
}
