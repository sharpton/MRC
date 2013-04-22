-- MySQL dump 10.13  Distrib 5.5.29, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: SFams_MH
-- ------------------------------------------------------
-- Server version	5.5.29-0ubuntu0.12.04.1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `analysis`
--

DROP TABLE IF EXISTS `analysis`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `analysis` (
  `analysisid` int(10) NOT NULL AUTO_INCREMENT,
  `project_id` int(10) unsigned NOT NULL,
  `famid` int(10) NOT NULL,
  `treeid` int(10) DEFAULT NULL,
  `statistics` text,
  PRIMARY KEY (`analysisid`),
  KEY `projectid` (`project_id`),
  KEY `famid` (`famid`),
  KEY `treeid` (`treeid`),
  CONSTRAINT `analysis_ibfk_2` FOREIGN KEY (`famid`) REFERENCES `family` (`famid`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `analysis_ibfk_3` FOREIGN KEY (`treeid`) REFERENCES `trees` (`treeid`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `classification_parameters`
--

DROP TABLE IF EXISTS `classification_parameters`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `classification_parameters` (
  `classification_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `evalue_threshold` double DEFAULT NULL,
  `coverage_threshold` float DEFAULT NULL,
  `score_threshold` float DEFAULT NULL,
  `method` varchar(30) DEFAULT NULL,
  `reference_database_name` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`classification_id`),
  KEY `evalue_threshold` (`evalue_threshold`),
  KEY `coverage_threshold` (`coverage_threshold`),
  KEY `score_threshold` (`score_threshold`),
  KEY `method` (`method`),
  KEY `reference_database_name` (`reference_database_name`)
) ENGINE=InnoDB AUTO_INCREMENT=46 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `family`
--

DROP TABLE IF EXISTS `family`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `family` (
  `famid` int(10) NOT NULL AUTO_INCREMENT,
  `familyconstruction_id` int(11) NOT NULL COMMENT 'foreign key to familyconstruction',
  `fam_alt_id` varchar(256) DEFAULT NULL COMMENT 'This can/shoud be user as a secondary identifier for families. (e.g Pfam families could have "PF0001". ',
  `name` varchar(256) DEFAULT NULL,
  `description` varchar(512) DEFAULT NULL,
  `alnpath` text COMMENT 'Gives path to the file containing the alignment of all family members',
  `seed_alnpath` text,
  `hmmpath` text,
  `reftree` int(10) DEFAULT NULL,
  `alltree` int(10) DEFAULT NULL,
  `size` int(11) DEFAULT NULL COMMENT 'Number of sequences used to construct the family',
  `universality` int(11) DEFAULT NULL,
  `evenness` int(11) DEFAULT NULL,
  `arch_univ` int(11) DEFAULT NULL,
  `bact_univ` int(11) DEFAULT NULL,
  `euk_univ` int(11) DEFAULT NULL,
  `unknown_genes` int(11) DEFAULT NULL,
  `pathogen_percent` decimal(4,1) DEFAULT NULL,
  `aquatic_percent` decimal(4,1) DEFAULT NULL,
  PRIMARY KEY (`famid`),
  UNIQUE KEY `fam_alt_id` (`fam_alt_id`),
  KEY `familyconstruction_id` (`familyconstruction_id`),
  KEY `reftree` (`reftree`),
  KEY `alltree` (`alltree`),
  CONSTRAINT `family_ibfk_3` FOREIGN KEY (`familyconstruction_id`) REFERENCES `familyconstruction` (`familyconstruction_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `family_ibfk_6` FOREIGN KEY (`reftree`) REFERENCES `trees` (`treeid`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `family_ibfk_7` FOREIGN KEY (`alltree`) REFERENCES `trees` (`treeid`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=437857 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `familyconstruction`
--

DROP TABLE IF EXISTS `familyconstruction`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `familyconstruction` (
  `familyconstruction_id` int(11) NOT NULL AUTO_INCREMENT,
  `description` text NOT NULL COMMENT 'descripton of how the family was created',
  `name` varchar(50) NOT NULL,
  `author` varchar(30) NOT NULL,
  PRIMARY KEY (`familyconstruction_id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `familymembers`
--

DROP TABLE IF EXISTS `familymembers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `familymembers` (
  `familymember_id` int(11) NOT NULL AUTO_INCREMENT,
  `famid` int(10) NOT NULL COMMENT 'Foreign key to "family" table',
  `gene_oid` int(10) unsigned DEFAULT NULL COMMENT 'foreign key to "genes" table',
  `orf_id` int(11) unsigned DEFAULT NULL COMMENT 'foreign key to "orfs" table',
  `classification_id` int(10) unsigned DEFAULT NULL COMMENT 'foreign key to classification_parameters table',
  PRIMARY KEY (`familymember_id`),
  KEY `protein_id` (`gene_oid`),
  KEY `famid` (`famid`),
  KEY `orfid` (`orf_id`),
  KEY `classification_id` (`classification_id`),
  CONSTRAINT `familymembers_ibfk_2` FOREIGN KEY (`famid`) REFERENCES `family` (`famid`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `familymembers_ibfk_4` FOREIGN KEY (`gene_oid`) REFERENCES `genes` (`gene_oid`) ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT `familymembers_ibfk_5` FOREIGN KEY (`orf_id`) REFERENCES `orfs` (`orf_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `familymembers_ibfk_6` FOREIGN KEY (`classification_id`) REFERENCES `classification_parameters` (`classification_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=6741433 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `genes`
--

DROP TABLE IF EXISTS `genes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `genes` (
  `gene_oid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `taxon_oid` int(10) unsigned NOT NULL,
  `protein_id` varchar(15) DEFAULT NULL,
  `type` varchar(64) NOT NULL,
  `start` int(10) unsigned NOT NULL,
  `end` int(10) unsigned NOT NULL,
  `strand` enum('-1','0','1') NOT NULL,
  `locus` varchar(30) NOT NULL,
  `name` varchar(100) DEFAULT NULL,
  `description` varchar(1000) NOT NULL,
  `dna` text NOT NULL,
  `protein` text,
  `scaffold_name` varchar(30) NOT NULL,
  `scaffold_id` varchar(15) NOT NULL,
  PRIMARY KEY (`gene_oid`),
  KEY `genomes` (`taxon_oid`),
  KEY `protein_id` (`protein_id`),
  KEY `name` (`name`),
  CONSTRAINT `genes_ibfk_1` FOREIGN KEY (`taxon_oid`) REFERENCES `genomes` (`taxon_oid`) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB AUTO_INCREMENT=650643204 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `genomes`
--

DROP TABLE IF EXISTS `genomes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `genomes` (
  `taxon_oid` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `ncbi_taxon_id` int(10) unsigned NOT NULL,
  `ncbi_project_id` int(10) unsigned NOT NULL,
  `completion` enum('Draft','Finished','Permanent Draft') NOT NULL,
  `domain` enum('Bacteria','Archaea','Eukaryota') NOT NULL,
  `name` varchar(256) NOT NULL,
  `directory` varchar(100) NOT NULL,
  `phylum` varchar(25) NOT NULL,
  `class` varchar(30) NOT NULL,
  `order` varchar(30) NOT NULL,
  `family` varchar(50) NOT NULL,
  `genus` varchar(50) NOT NULL,
  `sequencing_center` text NOT NULL,
  `gene_count` int(10) NOT NULL,
  `genome_size` int(25) NOT NULL,
  `scaffold_count` int(10) NOT NULL,
  `img_release` varchar(15) NOT NULL,
  `add_date` varchar(15) NOT NULL,
  `is_public` enum('Yes','No') NOT NULL,
  `gc` decimal(3,1) DEFAULT NULL,
  `gram_stain` enum('+','-') DEFAULT NULL,
  `shape` text,
  `arrangement` text,
  `endospores` text,
  `motility` text,
  `salinity` text,
  `oxygen_req` text,
  `habitat` text,
  `temp_range` text,
  `pathogenic_in` text,
  `disease` text,
  PRIMARY KEY (`taxon_oid`),
  KEY `ncbi_taxon_id` (`ncbi_taxon_id`)
) ENGINE=InnoDB AUTO_INCREMENT=650377992 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `metareads`
--

DROP TABLE IF EXISTS `metareads`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `metareads` (
  `read_id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `sample_id` int(11) unsigned NOT NULL,
  `read_alt_id` varchar(256) NOT NULL,
  `seq` text DEFAULT NULL,
  PRIMARY KEY (`read_id`),
  UNIQUE KEY `sample_id_read_alt_id` (`sample_id`,`read_alt_id`),
  KEY `sampleid` (`sample_id`),
  CONSTRAINT `metareads_ibfk_1` FOREIGN KEY (`sample_id`) REFERENCES `samples` (`sample_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=71062786 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `orfs`
--

DROP TABLE IF EXISTS `orfs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `orfs` (
  `orf_id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `sample_id` int(11) unsigned NOT NULL,
  `read_id` int(11) unsigned DEFAULT NULL,
  `orf_alt_id` varchar(256) NOT NULL,
  `start` int(5) DEFAULT NULL,
  `stop` int(5) DEFAULT NULL,
  `frame` enum('0','1','2') DEFAULT NULL,
  `strand` enum('-','+') DEFAULT NULL,
  `seq` text DEFAULT NULL,
  PRIMARY KEY (`orf_id`),
  UNIQUE KEY `sample_id_orf_alt_id` (`sample_id`,`orf_alt_id`),
  KEY `readid` (`read_id`),
  KEY `sample_id` (`sample_id`),
  CONSTRAINT `orfs_ibfk_1` FOREIGN KEY (`read_id`) REFERENCES `metareads` (`read_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `orfs_ibfk_2` FOREIGN KEY (`sample_id`) REFERENCES `samples` (`sample_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=22649737 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `project`
--

DROP TABLE IF EXISTS `project`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `project` (
  `project_id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(64) DEFAULT NULL,
  `description` text,
  PRIMARY KEY (`project_id`)
) ENGINE=InnoDB AUTO_INCREMENT=87 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `rnasequences`
--

DROP TABLE IF EXISTS `rnasequences`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `rnasequences` (
  `sequence_id` int(25) NOT NULL AUTO_INCREMENT,
  `alt_sequence_id` varchar(25) NOT NULL,
  `type` enum('ssu','lsu') NOT NULL,
  `start` int(10) DEFAULT NULL COMMENT 'Start coordinate',
  `end` int(10) DEFAULT NULL COMMENT 'End coordinate',
  `sampleid` int(10) DEFAULT NULL,
  `sequence` text NOT NULL,
  PRIMARY KEY (`sequence_id`)
) ENGINE=MyISAM AUTO_INCREMENT=1427030 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `samples`
--

DROP TABLE IF EXISTS `samples`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `samples` (
  `sample_id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `project_id` int(11) unsigned DEFAULT NULL,
  `sample_alt_id` varchar(256) NOT NULL,
  `name` varchar(128) DEFAULT NULL,
  `description` text,
  `country` varchar(256) DEFAULT NULL,
  `gender` varchar(64) DEFAULT NULL,
  `age` int(10) unsigned DEFAULT NULL COMMENT 'Age of patient that sample was taken from',
  `bmi` decimal(5,2) DEFAULT NULL COMMENT 'Body Mass Index',
  `ibd` tinyint(1) DEFAULT NULL COMMENT 'Irritable Bowel Syndrome',
  `crohn_disease` tinyint(1) DEFAULT NULL COMMENT 'Crohn''s disease',
  `ulcerative_colitis` tinyint(1) DEFAULT NULL COMMENT 'ulcerative colitis',
  `location` varchar(256) DEFAULT NULL,
  `datesampled` varchar(25) DEFAULT NULL COMMENT 'date_sampled',
  `site_id` varchar(256) DEFAULT NULL,
  `region` varchar(256) DEFAULT NULL,
  `depth` varchar(256) DEFAULT NULL,
  `water_depth` varchar(256) DEFAULT NULL,
  `salinity` varchar(256) DEFAULT NULL,
  `temperature` varchar(256) DEFAULT NULL,
  `volume_filtered` varchar(256) DEFAULT NULL,
  `chlorophyll_density` varchar(512) DEFAULT NULL,
  `annual_chlorophyll_density` varchar(512) DEFAULT NULL,
  `other_metadata` text,
  PRIMARY KEY (`sample_id`),
  UNIQUE KEY `sample_alt_id` (`sample_alt_id`),
  UNIQUE KEY `project_id_sample_alt_id` (`project_id`,`sample_alt_id`),
  KEY `project_id` (`project_id`),
  CONSTRAINT `samples_ibfk_1` FOREIGN KEY (`project_id`) REFERENCES `project` (`project_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=97 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `searchresults_old`
--

DROP TABLE IF EXISTS `searchresults_old`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `searchresults_old` (
  `searchresults_id` int(11) NOT NULL AUTO_INCREMENT,
  `orf_id` int(11) unsigned NOT NULL,
  `famid` int(10) NOT NULL,
  `evalue` double DEFAULT NULL,
  `score` float DEFAULT NULL,
  `other_searchstats` text,
  PRIMARY KEY (`searchresults_id`),
  UNIQUE KEY `orf_id_famid` (`orf_id`,`famid`),
  KEY `orfid` (`orf_id`),
  KEY `famid` (`famid`),
  CONSTRAINT `searchresults_ibfk_1` FOREIGN KEY (`famid`) REFERENCES `family` (`famid`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `searchresults_ibfk_2` FOREIGN KEY (`orf_id`) REFERENCES `orfs` (`orf_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `trees`
--

DROP TABLE IF EXISTS `trees`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `trees` (
  `treeid` int(10) NOT NULL AUTO_INCREMENT,
  `treedesc` text,
  `treepath` text,
  `treetype` enum('REFERENCE','ALL') DEFAULT NULL,
  PRIMARY KEY (`treeid`)
) ENGINE=InnoDB AUTO_INCREMENT=436354 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `unknowngenes`
--

DROP TABLE IF EXISTS `unknowngenes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `unknowngenes` (
  `gene_oid` int(10) unsigned NOT NULL,
  `pfam` varchar(50) DEFAULT NULL,
  `product` enum('Yes','No') DEFAULT NULL,
  `name` enum('Yes','No') DEFAULT NULL,
  PRIMARY KEY (`gene_oid`),
  CONSTRAINT `unknowngenes_ibfk_1` FOREIGN KEY (`gene_oid`) REFERENCES `genes` (`gene_oid`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COMMENT='Contains a  list of genes with unknown function';

--
-- Table structure for table `familymembers_slim`
--

/*This and classification_id are the only tables that must/will have data when running MRC with the --slim option. All other data is in ffdb*/
DROP TABLE IF EXISTS `familymembers_slim`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `familymembers_slim` (
  `familymember_id_slim` int(11) NOT NULL AUTO_INCREMENT,
  `famid_slim` int(10) NOT NULL, 
  `orf_alt_id_slim` varchar(256) NOT NULL,
  `sample_id` int(11) unsigned NOT NULL, /*NOTE NO FOREIGN KEY CHECK!*/
  `classification_id` int(10) unsigned NOT NULL, /*NOTE NO FOREIGN KEY CHECK!*/
  PRIMARY KEY (`familymember_id_slim`),
  UNIQUE KEY `orf_fam_sample_class_id` (`orf_alt_id_slim`,`famid_slim`,`sample_id`,`classification_id`), /*THIS IS FOR SAFETY*/
  KEY `famid_slim` (`famid_slim`),
  KEY `classification_id` (`classification_id`),
  KEY `sample_id` (`sample_id`),
  CONSTRAINT `searchresults_ibfk_1` FOREIGN KEY (`sample_id`) REFERENCES `samples` (`sample_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `searchresults_ibfk_2` FOREIGN KEY (`classification_id`) REFERENCES `classification_parameters` (`classification_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `searchresults`
--

DROP TABLE IF EXISTS `searchresults`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `searchresults` (
  `searchresults_id` int(11) NOT NULL AUTO_INCREMENT,
  `orf_alt_id` varchar(256) NOT NULL, /*FASTER FOR WORKFLOW IF WE STORE ALT_ID*/
  `read_alt_id` varchar(256) NOT NULL, /*FASTER FOR WORKFLOW IF WE STORE ALT_ID*/
  `sample_id` int(11) unsigned NOT NULL, /*NOTE NO FOREIGN KEY CHECK!*/
  `famid` int(10) NOT NULL, /*NOTE NO FOREIGN KEY CHECK!*/
  `classification_id` int(10) unsigned NOT NULL, /*NOTE NO FOREIGN KEY CHECK!*/
  `score` float DEFAULT NULL,
  `evalue` double DEFAULT NULL,
  `orf_coverage` float DEFAULT NULL,
  PRIMARY KEY (`searchresults_id`),
  UNIQUE KEY `orf_fam_sample_class_id` (`orf_alt_id`,`famid`,`sample_id`,`classification_id`), /*THIS IS FOR SAFETY*/ 
  KEY `orfaltid` (`orf_alt_id`),
  KEY `famid` (`famid`),
  KEY `readaltid` (`read_alt_id`),
  KEY `sampleid` (`sample_id`),
  CONSTRAINT `searchresults_ibfk_1` FOREIGN KEY (`sample_id`) REFERENCES `samples` (`sample_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `searchresults_ibfk_2` FOREIGN KEY (`classification_id`) REFERENCES `classification_parameters` (`classification_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;


/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2013-02-28 14:33:29
