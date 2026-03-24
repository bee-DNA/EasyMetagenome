d <- read.csv('.inline_rscript_e.csv', check.names = FALSE, stringsAsFactors = FALSE)
if (nrow(d) == 0) {
  cat('NO_INLINE_SNIPPETS\n')
  quit(status = 0)
}
bad <- 0L
for (i in seq_len(nrow(d))) {
  code <- d$code[i]
  ok <- TRUE
  msg <- ''
  tryCatch(parse(text = code), error = function(e) {
    ok <<- FALSE
    msg <<- conditionMessage(e)
  })
  if (ok) {
    cat(sprintf('OK\t%s:%s\n', d$path[i], d$line[i]))
  } else {
    cat(sprintf('FAIL\t%s:%s\t%s\n', d$path[i], d$line[i], msg))
    bad <- bad + 1L
  }
}
cat(sprintf('SUMMARY\t%d\t%d\n', nrow(d) - bad, bad))
if (bad > 0) quit(status = 2)
