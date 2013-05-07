library(ggplot2)
#Build a function that groups samples by some metadata parameter, has format similar to following. Need to think about function...
# Sample Num_Reads  Class_Reads Class_Ratio     Type     Data_Pair
# 109    446897	  181580	0.406		MG	1
# 113    80615	  29914		0.371		MT	1
# 103    631084	  411616	0.652		MG 	2
# 108    73334	  41120		0.561		MT	2
#etc..

read.table( file = "classification_ratios.tab", header = TRUE )->rats
ggplot( rats, aes(x=Data_Pair, y=Class_Ratio, fill=Type )) + geom_bar(stat="identity", position="dodge")