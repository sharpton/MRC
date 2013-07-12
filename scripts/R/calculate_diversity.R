# Invoke %  R  --slave  --args  class.id  outdir  out.file.stem  metadata.tab <  calculate_diversity.R

#This script does the following:
#1. Calculates diversity summary statistics for each sample in the analysis
#2. Identifies intersample differences in diversity (producing plots and R data tables)
#3. Profiles the relative abundance variation of each family across samples (producing plots and R data tables)
#4. Conducts subsampled versions of the above analyses using sample metadata annotations

require(ggplot2)
require(reshape2)

Args             <- commandArgs()
class.id         <- Args[4]
outdir           <- Args[5] #must have trailing slash!
out.file.stem    <- Args[6]
fam.len.tab      <- Args[7] #contains average family sequence length, used to normalize abundances
metadata.tab     <- Args[8] #need to figure out how to automate building of this! Maybe we change sample table on the fly....
rare.value       <- Args[9] #need to check if it is defined or not...

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
     print( file )
     ggsave( filename = file, plot = last_plot() )    
     #sample RA (log scale)
     qplot( 1:length(RELATIVE_ABUNDANCE), rev(sort( log(RELATIVE_ABUNDANCE) ) ), data = samp.tab, geom="line", 
     	    main = paste( "Relative Abundance of Sample ", samp, sep="" ), 
	    xlab = "Family Rank", 
	    ylab = "Relative Abundance",
	    )
     file <- paste( outdir, out.file.stem, "sample_", samp, "_RA_log.pdf", sep="" )
     print( file )
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
  div.tab$SAMPLE_ORDERED <- factor( div.tab$SAMPLE_ID, meta[,1] )
  ggplot( div.tab, aes_string(  x="SAMPLE_ORDERED", y= div.type ) ) + 
    geom_bar( stat="identity" ) +
      labs( title = paste( "Per sample values for ", div.type, sep="" ) ) +
        xlab( "SAMPLE_ORDERED" ) +
          ylab( div.type )
  file <- paste( outdir, out.file.stem, "_project", project, "_", meta.type, "_by_", div.type, "_b.pdf", sep="" )     
  print(file)
  ggsave( filename = file, plot = last_plot() )    
}
#build boxplots, grouping by metadata fields. Not always informative (e.g., when field isn't discrete)
for( b in 1:length( meta.names ) ){
     for( d in 1:length( div.types ) ){
          div.type  <- div.types[d]
          meta.type <- meta.names[b]
          if( meta.type == "SAMPLE_ID" ){
            next;
          }
          ggplot( meta.div, aes_string( x = meta.type, y=div.type ) ) + 
           geom_boxplot( aes( fill = DATA_TYPE ) ) +
           labs( title = paste( div.type, " by ", meta.names[b], sep="" ) ) +
           xlab( meta.type ) +
           ylab( div.type )
          file <- paste( outdir, out.file.stem, "_project", project, "_", meta.type, "_by_", div.type, "_boxes.pdf", sep="" )     
          print(file)
          ggsave( filename = file, plot = last_plot() )    
     }
}
#build scatter plots, grouping my metadata fields. Not always informative (e.g., when field is discrete)
for( b in 1:length( meta.names ) ){
     for( d in 1:length( div.types ) ){
          div.type  <- div.types[d]
   	  meta.type <- meta.names[b]
          if( meta.type== "SAMPLE_ID" ){
            next;
          }
	  ggplot( meta.div, aes_string( x = meta.type, y=div.type ) ) +
           geom_point( aes( colour = DATA_TYPE ) ) +
           labs( title    = paste( div.type," by ", meta.names[b], sep="" ) ) +
           xlab( meta.type ) +
           ylab( div.type )
          file <- paste( outdir, out.file.stem, "_project", project, "_", meta.type, "_by_", div.type, "_scatter.pdf", sep="" )     
          print( file )
          ggsave( filename = file, plot = last_plot() )    
     }
}
for( b in 1:length( meta.names ) ){
  for( d in 1:length( div.types ) ){
    div.type  <- div.types[d]
    meta.type <- meta.names[b]
    if( meta.type != "SAMPLE_ID" ){
      next;
    }
    ggplot( meta.div, aes_string( x = meta.type, y=div.type ) ) +
      geom_line( aes( colour = DATA_TYPE ) ) +
        labs( title    = paste( div.type," by ", meta.names[b], sep="" ) ) +
          xlab( meta.type ) +
            ylab( div.type )
    file <- paste( outdir, out.file.stem, "_project", project, "_", meta.type, "_by_", div.type, "_lines.pdf", sep="" )
    print( file )
    ggsave( filename = file, plot = last_plot() )
  }
}

########################
# INTERFAMILY ANALYSIS #
########################
#order samples by the relative abundance of families across all samples
#have to do some melting & casting to place 0 values in matrix of samples x fams
proj.tab.m    <- melt( proj.tab, id=c("SAMPLE_ID", "FAMILY_ID") )
proj.tab.m.ra <- subset( proj.tab.m, proj.tab.m$variable == "RELATIVE_ABUNDANCE" )
proj.ra.cast  <- acast( proj.tab.m.ra, SAMPLE_ID ~ FAMILY_ID, value.var="value" ) #This produces a matrix
proj.ra.cast[is.na(proj.ra.cast)] <- 0 #replace NAs with 0
class(proj.ra.cast) <- "numeric" #force matrix values to be numeric in the case where they were character
proj.ra.cast.t <- t(proj.ra.cast) #a matrix of family RA across samples

for( a in 0:length( meta.names ) ){
  if( a == 0 ){ #summary data across samples
    sub.tab        <- proj.ra.cast.t #we'll work with the entire set
    sub.tab.func   <- apply( sub.tab, 1, max ) #apply a function to help determine how to sort families
    fam.sort       <- sort( sub.tab.func, decreasing=TRUE ) #sort families by their median value across samples
    fam.sort.names <- names( fam.sort ) #ordered list of famids
    proj.ra        <- melt( sub.tab ) #this is the sample by fam by ra df that we want for plotting, with 0 values present
    colnames(proj.ra) <- c("Family", "Sample", "RelativeAbundance" )
    proj.ra$famid <- proj.ra$Family #create a dimension that we'll turn into ordered factor
    proj.ra$famid <- factor( proj.ra$famid, levels = fam.sort.names ) #create the factor
    #plot per family statistics - each fam gets a series of stats based on RA across samples
    fam.vars      <- apply( sub.tab, 1, var )
    fam.max       <- apply( sub.tab, 1, max )
    fam.meds      <- apply( sub.tab, 1, median )
    fam.means     <- apply( sub.tab, 1, mean )
    fam.min       <- apply( sub.tab, 1, min )
    fam.stats     <- data.frame( famid=names(fam.vars), variance=fam.vars, maximum=fam.max, median=fam.meds, mean=fam.means, minimum=fam.min )
    fam.stats$sorted <- fam.stats$famid #create a factor of sorted famids 
    fam.stats$sorted <- factor( fam.stats$sorted, levels = fam.sort.names ) 
    for( c in 1:length( colnames( fam.stats ) ) ){
      stat <- colnames(fam.stats)[c]
      if( stat == "famid" ){
        next
      }
      ggplot( fam.stats, aes_string( x = "sorted", y = stat ) ) + geom_bar( stat = "identity", position = "dodge" ) +
        ylab( "Relative Abundance" ) +
          xlab( "Family Rank" ) +
            theme( axis.text.x = element_blank() ) +
              labs( title = paste( "Protein Family Frequencies Across all Samples" ) )
      file <- paste( outdir, out.file.stem, "interFamilyAnalysis_project", project, "_ALL_bySample.pdf", sep="" )     
      print( file )
      ggsave( filename=file, plot = last_plot() )          
    }
    
    #plot the per family abundance across samples
    proj.ra.sub   <- subset( proj.ra, proj.ra$Family %in% fam.sort.names[1:100] )
    ggplot( proj.ra.sub, aes( x = famid, y = RelativeAbundance, fill = as.character( Sample )) ) + geom_bar( stat = "identity", position = "dodge" ) +
      ylab( "Relative Abundance" ) +
        xlab( "Family Rank" ) +
          theme( axis.text.x = element_blank() ) +
            labs( title = paste( "Protein Family Frequencies Across all Samples" ) )
    file <- paste( outdir, out.file.stem, "interFamilyAnalysis_project", project, "_ALL_bySample.pdf", sep="" )     
    print( file )
    ggsave( filename=file, plot = last_plot() )    
  } else { #summarize families based on RA in specific types of samples
    meta.field <- meta.names[a]
    if( meta.field == "SAMPLE_ID" ){
      next
    }
    types      <- unique( meta[,a] )
    for( b in 1:length( types ) ){
      type           <- types[b]
      sub.samps      <- subset( meta$SAMPLE_ID, meta[,a] == type ) 
      sub.tab        <- proj.ra.cast.t[,as.character(sub.samps)] #we will look at only this particular set of samples
      sub.tab.func   <- apply( sub.tab, 1, max ) #apply a function to help determine how to sort families
      fam.sort       <- sort( sub.tab.func, decreasing=TRUE ) #sort families by their median value across samples
      fam.sort.names <- names( fam.sort ) #ordered list of famids
      proj.ra        <- melt( sub.tab ) #this is the sample by fam by ra df that we want for plotting, with 0 values present
      colnames(proj.ra) <- c("Family", "Sample", "RelativeAbundance" )
      proj.ra$famid <- proj.ra$Family #create a dimension that we'll turn into ordered factor
      proj.ra$famid <- factor( proj.ra$famid, levels = fam.sort.names ) #create the factor      
      proj.ra.sub   <- subset( proj.ra, proj.ra$Family %in% fam.sort.names[1:100] )
      ggplot( proj.ra.sub, aes( x = famid, y = RelativeAbundance, fill = as.character( Sample )) ) + geom_bar( stat = "identity", position = "dodge" ) +
        ylab( "Relative Abundance" ) +
          xlab( "Family Rank" ) +
            theme( axis.text.x = element_blank() ) +
              labs( title = paste( "Protein Family Frequencies Across all Samples" ) )
      file <- paste( outdir, out.file.stem, "_interFamilyAnalysis_project", project, "_", meta.field, "_", type, "_bySample.pdf", sep="" )     
      print( file )
      ggsave( filename=file, plot = last_plot() )
    }
  }
}
  
                   
