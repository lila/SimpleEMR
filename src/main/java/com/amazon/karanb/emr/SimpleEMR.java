// Simple EMR application that reads fasta files and does nothing in particular with them.
//
// used for tutorial or performance testing emr clusters
// karan bhatia, karanb@amazon.com


package com.amazon.karanb.emr;

import gov.jgi.meta.hadoop.input.FastaInputFormat;
import gov.jgi.meta.sequence.SequenceString;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.Mapper;
import org.apache.hadoop.mapreduce.Reducer;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.hadoop.util.GenericOptionsParser;
import org.apache.log4j.Logger;

import java.io.IOException;
import java.util.Enumeration;
import java.util.Properties;

public class SimpleEMR {

    /*
     * private member variables
     */
    static Logger log = Logger.getLogger(SimpleEMR.class);


    /**
     * simple map class that reads data and then throws it away.  the output is always <"total", 1>
     */
    public static class SimpleMapper
            extends Mapper<Text, Text, Text, LongWritable> {

        int mapcount = 0;  // to count the number of map tasks

        /** map task, read sequences with sequence id, seqid, and output key/value "total"/1
         *
         * @param seqid the sequence id from the fasta file
         * @param s the compressed sequence
         * @param context hadoop context
         * @throws IOException
         * @throws InterruptedException
         */
        public void map(Text seqid, Text s, Context context) throws IOException, InterruptedException {
            mapcount++;
            long numBasePairs = SequenceString.numBases(SequenceString.sequenceToByteArray(s.toString()));
            context.write(new Text("total"), new LongWritable(numBasePairs));
        }
    }

    /** simple reducer class that sums the values of each key
     *
     * output will equal the total number of map tasks completed
     */
    public static class SimpleReducer extends Reducer<Text, LongWritable, Text, LongWritable> {

        /** sum all the values of for each key
         *
         * @param key
         * @param values
         * @param context
         * @throws InterruptedException
         * @throws IOException
         */
        public void reduce(Text key, Iterable<LongWritable> values, Context context)
                throws InterruptedException, IOException {

            Long total = 0L;

            for (LongWritable t : values) {
                total += t.get();
            }
            context.write(key, new LongWritable(total));
        }
    }

    private static String[] loadConfiguration(Configuration conf, String[] args)
            throws IOException
    {
        return loadConfiguration(conf, null, args);
    }

    private static String[] loadConfiguration(Configuration conf, String configurationFileName, String[] args)
            throws IOException
    {
        /*
        * first load the configuration from the build properties (typically packaged in the jar)
        */
        System.out.println("loading application.properties ...");
        try {
            Properties buildProperties = new Properties();
            buildProperties.load(SimpleEMR.class.getResourceAsStream("/application.properties"));
            for (Enumeration e = buildProperties.propertyNames(); e.hasMoreElements(); ) {
                String k = (String) e.nextElement();
                System.out.println("setting " + k + " to " + buildProperties.getProperty(k));
                System.setProperty(k, buildProperties.getProperty(k));
                conf.set(k, buildProperties.getProperty(k));
            }
        } catch (Exception e) {
            System.out.println("unable to find application.properties ... skipping");
        }
        /*
        finally, allow user to override from commandline
         */
        return new GenericOptionsParser(conf, args).getRemainingArgs();
    }


    private static void printConfiguration(Configuration conf, Logger log, String[] allProperties) {

        for (String option : allProperties) {

            if (option.startsWith("---")) {
                log.info(option);
                continue;
            }
            String c = conf.get(option);
            if (c != null) {
                log.info("\toption " + option + ":\t" + c);
            }
        }
    }

    /**
     * starts off the hadoop application
     *
     * @param args input fasta sequence and output location
     * @throws Exception
     */
    public static void main(String[] args) throws Exception {

        /*
        load the application configuration parameters (from deployment directory)
         */

        Configuration conf = new Configuration();
        String[] otherArgs = loadConfiguration(conf, args);

        /*
        process arguments
         */
        if (otherArgs.length != 2) {
            System.err.println("Usage: SimpleEMR <fasta seq url> <output url>");
            System.exit(2);
        }

        /*
         * seems to help in file i/o performance
         */
        conf.setInt("io.file.buffer.size", 1024 * 1024);

        log.info(System.getProperty("application.name") + "[version " + System.getProperty("application.version") + "] starting with following parameters");
        log.info("\tsequence file: " + otherArgs[0]);
        log.info("\toutput dir: " + otherArgs[1]);

        String[] allProperties = {
                "--- application properties ---",
                "application.name",
                "application.version",
                "--- system properties ---",
                "mapred.min.split.size",
                "mapred.max.split.size"
        };

        printConfiguration(conf, log, allProperties);

        Job job = new Job(conf, System.getProperty("application.name") + "-" + System.getProperty("application.version") + "-step1");
        job.setJarByClass(SimpleEMR.class);
        job.setMapperClass(SimpleMapper.class);
        job.setInputFormatClass(FastaInputFormat.class);
        job.setMapOutputKeyClass(Text.class);
        job.setMapOutputValueClass(LongWritable.class);
        job.setReducerClass(SimpleReducer.class);
        job.setCombinerClass(SimpleReducer.class);
        job.setNumReduceTasks(1); // force there to be only 1 to get a single output file

        FileInputFormat.addInputPath(job, new Path(otherArgs[0]));
        FileOutputFormat.setOutputPath(job, new Path(otherArgs[1] + "/step1"));

        System.exit(job.waitForCompletion(true) ? 0 : 1);
    }
}

