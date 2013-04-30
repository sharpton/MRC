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
  KEY `orfalt_sample_id` (`orf_alt_id`,`sample_id`),
  KEY `famid` (`famid`),
  KEY `readalt_sample_id` (`read_alt_id`,`sample_id`),
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
