# Invoke %  R  --slave  --args  class.id  outdir  out.file.stem  metadata.tab <  calculate_diversity.R

require(ggplot2)

Args             <- commandArgs()
class.id         <- Args[4]
outdir           <- Args[5] #must have trailing slash!
out.file.stem    <- Args[6]
metadata.tab     <- Args[7] #need to figure out how to automate building of this! Maybe we change sample table on the fly....

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

#get the metadata
meta       <- read.table( file=metadata.tab, header = TRUE )
meta.names <- colnames( meta )

#get the classification maps associated with the class.id
maps     <- list.files(pattern=paste('ClassificationMap_Sample_.*_ClassID_', class.id, '.tab',sep='' ))
proj.tab <- NULL #cats samp.tabs together
div.tab  <- NULL #maps sample id to family relative abundance shannon entropy and richness
div.types <- c( "RICHNESS" , "RELATIVE_RICHNESS", "SHANNON_ENTROPY" )

for( a in 1:length(maps) ){
     #build a new sample classification table
     samp.tab     <- NULL
     class.map    <- read.table( file=maps[a], header = TRUE )
     FAMID_FACTOR <- as.factor( class.map$FAMID )
     samp         <- unique( class.map$SAMPLE_ID )
     famids       <- levels( FAMID_FACTOR )
     counts       <- table( FAMID_FACTOR ) #maps family id to family counts
     read.count   <- class.map$READ_COUNT[1]
     project      <- class.map$PROJECT_ID[1]
     samp.tab     <- data.frame( project, samp, counts, read.count, as.numeric(counts)/read.count )
     colnames(samp.tab) <- c( "PROJECT_ID", "SAMPLE_ID", "FAMILY_ID", "ABUNDANCE", "READ_COUNT", "RELATIVE_ABUNDANCE" )
     
     #Build diversity table for sample
     #get classification statistics
     samp.div     <- NULL
     class.count  <- dim(class.map)[1]
     class.ratio  <- class.count / read.count    
     #calculate diversity metrics
     richness     <- length( unique( famids ) )              
     rel.richness <- richness / read.count
     shannon      <- sh.entropy( samp.tab$RELATIVE_ABUNDANCE )
     samp.div     <- data.frame( SAMPLE_ID=samp, NUM_READS=read.count, CLASS_READS=class.count, CLASS_RATIO=class.ratio, RICHNESS=richness, RELATIVE_RICHNESS=rel.richness, SHANNON_ENTROPY=shannon )
     div.tab      <- rbind( div.tab, samp.div )

     #Make Sample Plots
     #sample RA
     qplot( 1:length(RELATIVE_ABUNDANCE), rev(sort( RELATIVE_ABUNDANCE )    )  , data = samp.tab, geom="line", 
     	    main = paste( "Relative Abundance of Sample ", samp, sep="" ), 
	    xlab = "Family Rank", 
	    ylab = "Relative Abundance", 
	    )
     file <- paste( outdir, out.file.stem, "sample_", samp, "_RA.pdf", sep="" ) 
     ggsave( filename = file, plot = last_plot() )    
     #sample RA (log scale)
     qplot( 1:length(RELATIVE_ABUNDANCE), rev(sort( log(RELATIVE_ABUNDANCE) ) ), data = samp.tab, geom="line", 
     	    main = paste( "Relative Abundance of Sample ", samp, sep="" ), 
	    xlab = "Family Rank", 
	    ylab = "Relative Abundance",
	    )
     file <- paste( outdir, out.file.stem, "sample_", samp, "_RA_log.pdf", sep="" )     
     ggsave( filename = file, plot = last_plot() )    
     #add to proj.tab
     proj.tab <- rbind( proj.tab, samp.tab )
}

meta.div   <- merge( div.tab, meta, by = "SAMPLE_ID" )
#build per sample bar plots
for( b in 1:length( colnames(div.tab) ) ){
          div.type <- colnames(div.tab)[b]
	  if( div.type == "SAMPLE_ID" ){
	      next
	  }
	  #may want to figure how to automate reordering...
	  meta.div$SAMPLE_ORDERED <- factor( meta.div$SAMPLE_ID, meta[,1] )
          ggplot( meta.div, aes_string(  x="SAMPLE_ORDERED", y= div.type ) ) + 
           geom_bar( stat="identity", aes( fill = DATA_TYPE ) ) +
           labs( title = paste( "Per sample values for ", div.type, sep="" ) ) +
           xlab( "SAMPLE_ORDERED" ) +
           ylab( div.type )
          file <- paste( outdir, out.file.stem, "_project", project, "_", meta.type, "_by_", div.type, "_boxes.pdf", sep="" )     
          ggsave( filename = file, plot = last_plot() )    
}
#build boxplots, grouping by metadata fields. Not always informative (e.g., when field isn't discrete)
for( b in 1:length( meta.names ) ){
     for( d in 1:length( div.types ) ){
          div.type  <- div.types[d]
          meta.type <- meta.names[b]
          ggplot( meta.div, aes_string( x = meta.type, y=div.type ) ) + 
           geom_boxplot( aes( fill = DATA_TYPE ) ) +
           labs( title = paste( div.type, " by ", meta.names[b], sep="" ) ) +
           xlab( meta.type ) +
           ylab( div.type )
          file <- paste( outdir, out.file.stem, "_project", project, "_", meta.type, "_by_", div.type, "_boxes.pdf", sep="" )     
          ggsave( filename = file, plot = last_plot() )    
     }
}
#build scatter plots, grouping my metadata fields. Not always informative (e.g., when field is discrete)
for( b in 1:length( meta.names ) ){
     for( d in 1:length( div.types ) ){
          div.type  <- div.types[d]
   	  meta.type <- meta.names[b]
	  ggplot( meta.div, aes_string( x = meta.type, y=div.type ) ) +
           geom_point( aes( colour = DATA_TYPE ) ) +
           labs( title    = paste( div.type," by ", meta.names[b], sep="" ) ) +
           xlab( meta.type ) +
           ylab( div.type )
          file <- paste( outdir, out.file.stem, "_project", project, "_", meta.type, "_by_", div.type, "_lines.pdf", sep="" )     
         ggsave( filename = file, plot = last_plot() )    
     }
}

#Figure out how to plot stacked bar plots of ordered fams across samples
#ggplot( proj.tab, aes( x = FAMILY_ID, y = REL_ABUND, group=SAMPLE_ID ) ) + geom_line()