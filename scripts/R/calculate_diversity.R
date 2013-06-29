# Invoke %  R  --slave  --args  class.id  outdir  out.file.stem  metadata.tab <  calculate_diversity.R

require(ggplot2)

Args             <- commandArgs()
class.id         <- Args[4]
outdir           <- Args[5] #must have trailing slash!
out.file.stem    <- Args[6]
metadata.tab     <- Args[7] #need to figure out how to automate building of this! Maybe we change sample table on the fly....
rare.value       <- Args[8] #need to check if it is defined or not...

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
     goods        <- goods.coverage( samp.tab$ABUNDANCE, samp.tab$READ_COUNT[1] )
     samp.div     <- data.frame( SAMPLE_ID=samp, NUM_READS=read.count, CLASS_READS=class.count, CLASS_RATIO=class.ratio, RICHNESS=richness, RELATIVE_RICHNESS=rel.richness, SHANNON_ENTROPY=shannon, GOODS_COVERAGE=goods)
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
proj.tab <- NULL #cats samp.tabs together           div.type <- colnames(div.tab)[b]
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
#order samples by the relative abundance of families across all samples
#sort(proj.tab$RELATIVE_ABUNDANCE, decreasing=TRUE)
proj.tab$FAMILY <- as.numeric(as.vector(proj.tab$FAMILY_ID)) #get rid of family levels

proj.sort       <- proj.tab[with(proj.tab, order(-RELATIVE_ABUNDANCE)),]
proj.tab$FAMILY <- factor( proj.tab$FAMILY_ID, proj.sort$FAMILY_ID) #will spit warnings, safe to ignore
#get rid of unused factor levels (https://stat.ethz.ch/pipermail/r-help/2009-November/216878.html)
proj.tab$FAMILY <- factor( proj.tab$FAMILY ) #will spit warnings, safe to ignore. Will no longer get warnings on these factors afterwards

library(reshape2)
proj.sort.m    <- melt( proj.sort, id=c("SAMPLE_ID", "FAMILY") )
proj.sort.m.ra <- subset( proj.sort.m, proj.sort.m$variable == "RELATIVE_ABUNDANCE" )
proj.ra.cast   <- acast( proj.sort.m.ra, SAMPLE_ID ~ FAMILY ~ variable )
###PICK UP HERE!



ggplot( proj.sort.m.ra[1:100,], aes( x = FAMILY, y = value, fill = as.character(SAMPLE_ID) ) ) + geom_bar( stat = "identity", position = "dodge" ) +
      ylab( "Relative Abundance" ) +
      xlab( "Family Rank" ) +
      theme( axis.text.x = element_blank() ) +
      labs( title = paste( "Protein Family Frequencies Across all Samples" ) )



