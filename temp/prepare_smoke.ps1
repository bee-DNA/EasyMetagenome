$root = Join-Path $PWD "testdata/smoke"
$work = Join-Path $root "work"
$seq = Join-Path $work "seq"
$result = Join-Path $work "result"
$temp = Join-Path $work "temp"
$log = Join-Path $work "log"
$db = Join-Path $root "db"

$paths = @(
    $root,
    $work,
    $seq,
    $result,
    $temp,
    $log,
    $db,
    (Join-Path $db "metaphlan4"),
    (Join-Path $db "humann4/chocophlan"),
    (Join-Path $db "humann4/uniref"),
    (Join-Path $db "checkm2"),
    (Join-Path $db "eggnog"),
    (Join-Path $result "bins/TEST01"),
    (Join-Path $result "checkm2"),
    (Join-Path $result "metaphlan4"),
    (Join-Path $result "humann4/TEST01")
)

$paths | ForEach-Object { New-Item -ItemType Directory -Path $_ -Force | Out-Null }

Set-Content (Join-Path $seq "TEST01_1.fastq") -Encoding ascii -Value @(
    "@TEST01_1",
    "ACGTACGTACGT",
    "+",
    "FFFFFFFFFFFF"
)

Set-Content (Join-Path $seq "TEST01_2.fastq") -Encoding ascii -Value @(
    "@TEST01_2",
    "TGCATGCATGCA",
    "+",
    "FFFFFFFFFFFF"
)

Set-Content (Join-Path $result "bins/TEST01/bin.1.fa") -Encoding ascii -Value @(
    ">contig1",
    "ACGTACGTACGTACGTACGT"
)

Set-Content (Join-Path $result "checkm2/quality_report.tsv") -Encoding ascii -Value @(
    "#Bin Id`tCompleteness`tContamination",
    "bin.1`t95.0`t1.0"
)

Set-Content (Join-Path $result "metadata.txt") -Encoding ascii -Value @(
    "#SampleID`tGroup",
    "TEST01`tGroup1"
)

Set-Content (Join-Path $result "TEST01_taxa.tsv") -Encoding ascii -Value @(
    "#mpa_vJan25_CHOCOPhlAnSGB_202403",
    "k__Bacteria|p__Firmicutes|c__Bacilli|o__Lactobacillales|f__Lactobacillaceae|g__Lactobacillus|s__Lactobacillus_acidophilus`t100.0"
)

Set-Content (Join-Path $result "metaphlan4/taxonomy.tsv") -Encoding ascii -Value @(
    "clade_name`tTEST01_taxa",
    "k__Bacteria|p__Firmicutes|c__Bacilli|o__Lactobacillales|f__Lactobacillaceae|g__Lactobacillus|s__Lactobacillus_acidophilus`t100.0"
)

Set-Content (Join-Path $result "TEST01_genes.faa") -Encoding ascii -Value @(
    ">gene1",
    "MSTNPKPQRKTK"
)

Set-Content (Join-Path $result "humann4/TEST01/TEST01_genefamilies.tsv") -Encoding ascii -Value @(
    "# Gene Family`tTEST01",
    "UniRef90_A0A000`t10"
)

New-Item -ItemType File -Path (Join-Path $db "eggnog/eggnog.db") -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $db "eggnog/eggnog_proteins.dmnd") -Force | Out-Null

$envLines = @(
    "WORK_DIR=$work",
    "SEQ_DIR=$seq",
    "RESULT_DIR=$result",
    "TEMP_DIR=$temp",
    "LOG_DIR=$log",
    "DB_DIR=$db",
    "THREADS=2",
    "AUTO_METADATA=0"
)
Set-Content -Path (Join-Path $PWD ".env") -Value $envLines -Encoding ascii

Write-Output "Smoke fixture created at: $root"
Get-ChildItem -Recurse -File $root | Select-Object -First 30 FullName