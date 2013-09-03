# Invoke %  R  --slave  --args  abundance.file outdir outfile.stem <  calculate_sample_diversity.R

require(ggplot2)
require(reshape2)

Args             <- commandArgs()
abundance.file   <- Args[4]
outdir           <- Args[5] #must have trailing slash!
outfile.stem     <- Args[6]

#add trailing slash
outdir <- paste( outdir, "/", sep="" )
dir.create( file.path( outdir), showWarnings = FALSE )

                                        #Shannon Entropy Functions
#from SJ Riesenfeld
sh.entropy <- function(v,base=2) {
  p = as.numeric(v) / sum(v)
  sh.entropy = sum(sapply(v, coord.sh.entropy, base))
  return (sh.entropy)
}

coord.sh.entropy <- function(x, base=2) {
  if (x==0) {
    return (0)
  } else {
    return( -x*log(x, base) )
  }
}

#Good's coverage
#takes list of abundances per family and total number of reads across sample
goods.coverage <- function( abunds, count ) {
  singletons = length( subset( abunds, abunds == 1 ) )
  coverage   = 1 - ( singletons / count )
  return( coverage )
}

#get the metadata
meta       <- read.table( file=metadata.tab, header = TRUE )
meta.names <- colnames( meta )

#get the classification maps associated with the class.id
maps     <- list.files(pattern=paste('ClassificationMap_Sample_.*_ClassID_', class.id, '_Rare_', rare.value, '.tab',sep='' ))
proj.tab <- NULL #cats samp.tabs together
div.tab  <- NULL #maps sample id to family relative abundance shannon entropy and richness
div.types <- c( "RICHNESS" , "RELATIVE_RICHNESS", "SHANNON_ENTROPY", "GOODS_COVERAGE" )
