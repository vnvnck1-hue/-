param([string]$CatalogPath='art/catalog/catalog-data.json',[string]$ReportPath='art/special-icons/v1-complete/alpha-validation.json')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$catalog=Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$basePath=Split-Path -Parent ([IO.Path]::GetFullPath($CatalogPath))
$results=@()
foreach($item in $catalog.items){
 if(-not $item.image){throw "Missing image: $($item.id)"}
 $imagePath=[IO.Path]::GetFullPath((Join-Path $basePath $item.image))
 $bitmap=[Drawing.Bitmap]::new($imagePath)
 try{
  $cornerAlpha=@($bitmap.GetPixel(0,0).A,$bitmap.GetPixel($bitmap.Width-1,0).A,$bitmap.GetPixel(0,$bitmap.Height-1).A,$bitmap.GetPixel($bitmap.Width-1,$bitmap.Height-1).A)
  $cornerMax=($cornerAlpha | Measure-Object -Maximum).Maximum
  $transparent=0;$visible=0;$opaque=0
  for($sy=0;$sy -lt 40;$sy++){for($sx=0;$sx -lt 40;$sx++){
   $alpha=$bitmap.GetPixel([int][Math]::Floor($sx*$bitmap.Width/40),[int][Math]::Floor($sy*$bitmap.Height/40)).A
   if($alpha -eq 0){$transparent++};if($alpha -gt 1){$visible++};if($alpha -ge 240){$opaque++}
  }}
  $valid=($cornerMax -le 1 -and $transparent -gt 0 -and $visible -gt 0 -and $opaque -gt 0 -and $bitmap.PixelFormat.ToString().Contains('Argb'))
  $results+=[pscustomobject]@{id=$item.id;width=$bitmap.Width;height=$bitmap.Height;pixelFormat=$bitmap.PixelFormat.ToString();cornerAlphaMax=$cornerMax;transparentSamples=$transparent;visibleSamples=$visible;opaqueSamples=$opaque;valid=$valid}
 }finally{$bitmap.Dispose()}
}
$failed=@($results | Where-Object {-not $_.valid})
[pscustomobject]@{created='2026-10-11';total=$results.Count;failed=$failed.Count;items=$results} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
[pscustomobject]@{decoded=$results.Count;failed=$failed.Count;failures=@($failed.id);dimensions=@($results | Group-Object width,height | Select-Object Name,Count)} | ConvertTo-Json -Depth 4
if($failed.Count){exit 1}
