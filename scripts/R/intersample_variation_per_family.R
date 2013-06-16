# Invoke %  R  --slave  --args  class.id  outdir  out.file.stem  metadata.tab rare.value <  calculate_diversity.R
require(ggplot2)

Args             <- commandArgs()
class.id         <- Args[4]
outdir           <- Args[5] #must have trailing slash!
out.file.stem    <- Args[6]
metadata.tab     <- Args[7] #need to figure out how to automate building of this! Maybe we change sample table on the fly....
rare.value       <- Args[8] #need to check if it is defined or not...

#add trailing slash
outdir <- paste( outdir, "/", sep="" )

#get the metadata
meta       <- read.table( file=metadata.tab, header = TRUE )
meta.names <- colnames( meta )

#get the classification maps associated with the class.id
maps     <- list.files(pattern=paste('ClassificationMap_Sample_.*_ClassID_', class.id, '_Rare_', rare.value, '.tab',sep='' ))
proj.tab <- NULL #cats samp.tabs together
div.tab  <- NULL #maps sample id to family relative abundance shannon entropy and richness
div.types <- c( "RICHNESS" , "RELATIVE_RICHNESS", "SHANNON_ENTROPY" )

samp.tabs <- NULL #a df of sample tables, which we build in the code below
for( a in 1:length(maps) ){
  class.map    <- read.table( file=maps[a], header = TRUE )
  FAMID_FACTOR <- as.factor( class.map$FAMID )
  samp         <- unique( class.map$SAMPLE_ID )
  famids       <- levels( FAMID_FACTOR )
  counts       <- table( FAMID_FACTOR ) #maps family id to family counts
  read.count   <- class.map$READ_COUNT[1]
  project      <- class.map$PROJECT_ID[1]
  samp.tab     <- data.frame( samp, names(counts), as.numeric(counts)/read.count )
  colnames(samp.tab) <- c( "SAMPLE_ID", "FAMILY_ID", "RELATIVE_ABUNDANCE" )
  samp.tabs    <- rbind( samp.tabs, samp.tab )
}



#############################################################################################
# ORDER THE SAMPLES BY THEIR METADATA ORDER (PRESUMABLY, THIS IS THE ORDER WE WANT TO PLOT) #
#############################################################################################
samples  <- unique( samp.tabs$SAMPLE_ID )
samp.ord <- meta$SAMPLE_ID
samples  <- samples[as.character(samp.ord)]

#####################################################
# BUILD A FAMILY BY SAMPLE RELATIVE ABUNDANCE TABLE #
#####################################################
famids <- unique( samp.tabs$FAMILY_ID )
fam.ra.mat <- matrix( nrow = length( famids ), ncol = length( samples ), data = 0 )
colnames(fam.ra.mat)<-samples
rownames(fam.ra.mat)<-famids
for(b in 1:dim(samp.tabs)[1] ){
  row   <- samp.tabs[b,]
  famid <- row$FAMILY_ID
  samp.id <- row$SAMPLE_ID
  ra      <- row $RELATIVE_ABUNDANCE
  fam.ra.mat[as.character(famid),as.character(samp.id)] <- ra
}

#############################
# FOLD CHANGE NORMALIZATION #
#############################
foldchange.norm <- function( x ){ #assume a normal dist and calculate number of sd for each obs in set
  results  <- NULL
  fam.sd   <- sd(x)
  fam.mean <- mean(x)
  for( i in 1:length(x) ){
    obs     <- x[i]
    val     <- ( obs - fam.mean ) / fam.sd
    results <- c( results, val )
  }
  results
}

fam.norm.tab <- apply( fam.ra.tab, 1, foldchange.norm ) #this is a transpose of the dataframe above!

write.table( fam.norm.tab, file = paste(outdir, "family_ra_tab_by_samples_foldnorm.tab", sep=""))
