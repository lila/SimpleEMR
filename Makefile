# Makefile for SimpleEMR
#
# driver for various experiments with simpleEMR application.  
# assumes you have s3cmd and elastic mapreduce commandline utils
# set up and configured with your account access id/secret key
#
# run 
# % make
# to get the list of options.
#
# karnab@amazon.com

#
# commands setup (ADJUST THESE IF NEEDED)
# 
S3CMD                   = s3cmd
EMR			= elastic-mapreduce
CLUSTERSIZE		= 2
REGION                  = us-east
KEY			= normal
KEYPATH			= ${HOME}/.ssh/normal.pem

# 
# make targets 
#

help:
	@echo "help for Makefile for SimpleEMR sample project"
	@echo "make create           - create an EMR Cluster with default settings (10 x c1.medium)"
	@echo "make destroy          - clean up everything (terminate cluster and remove s3 bucket)"
	@echo
	@echo "make createlarge      - create cc1.4xlarge cluster"
	@echo "make createlargeopt   - create cc1.4xlarge cluster with max number of mappers"
	@echo "make createhuge       - create cc2.8xlarge cluster"
	@echo "make createhugeopt    - create cc2.8xlarge cluster with max number of mappers"
	@echo 
	@echo "make submitjob        - submit a job to the cluster with default settings"
	@echo "make submitoptimaljob - submit a job with optimized split size"
	@echo
	@echo "make logs             - show the stdout of job"
	@echo "make ssh              - log into head node of cluster"

#
# top level target for removing all derived data
#
clean: cleanbootstrap
	@echo "removed all unnecessary files"
	mvn clean

#
# removes all data copied to s3
#
cleanbootstrap:
	-${S3CMD} -r rb s3://$(USER).simple.emr/

#
# top level target to tear down cluster and cleanup everything
#
destroy: cleanbootstrap
	@ echo deleting server stack simple.emr
	-${EMR} -j `cat ./jobflowid` --terminate
	rm ./jobflowid
	rm ./numberOfMappers


#
# push data into s3 
#
bootstrap: ./target/SimpleEMR-0.1.0-job.jar
	-${S3CMD} mb s3://$(USER).simple.emr
	${S3CMD} sync --acl-public ./target/SimpleEMR-0.1.0-job.jar  s3://$(USER).simple.emr
	${S3CMD} sync --acl-public ./pig s3://${USER}.simple.emr/ 
	${S3CMD} sync --acl-public ./lib s3://${USER}.simple.emr/ 

#
# driver to build source code
#
./target/SimpleEMR-0.1.0-job.jar:
	mvn package

#
# top level target to create a new cluster of c1.mediums
#
create: 
	@ if [ -a ./jobflowid ]; then echo "jobflowid exists! exiting"; exit 1; fi
	@ echo creating EMR cluster
	${EMR} elastic-mapreduce --create --alive --name "$(USER)'s SimpleEMR Cluster" \
	--num-instances ${CLUSTERSIZE} \
	--instance-type c1.medium | cut -d " " -f 4 > ./jobflowid
	@ echo "2 * (${CLUSTERSIZE} - 1)" | bc  > ./numberOfMappers

# of cc1.4xlarge
createlarge: 
	@ echo creating EMR cluster
	${EMR} elastic-mapreduce --create --alive --name "$(USER)'s SimpleEMR Cluster" \
	--num-instances ${CLUSTERSIZE} \
	--instance-type cc1.4xlarge | cut -d " " -f 4 > ./jobflowid
	@ echo "12 * (${CLUSTERSIZE} - 1)" | bc  > ./numberOfMappers

createlargeopt:
	@ echo creating EMR cluster
	${EMR} elastic-mapreduce --create --alive --name "$(USER)'s SimpleEMR Cluster" \
	--num-instances ${CLUSTERSIZE} \
	--bootstrap-action s3://elasticmapreduce/bootstrap-actions/configure-hadoop --bootstrap-name "configure task slots" --args "-s,mapred.child.java.opts=-Xmx512m,-s,mapred.tasktracker.map.tasks.maximum=24" \
	--instance-type cc1.4xlarge | cut -d " " -f 4 > ./jobflowid
	@ echo "24 * (${CLUSTERSIZE} - 1)" | bc  > ./numberOfMappers


createhuge: 
	@ echo creating EMR cluster
	${EMR} elastic-mapreduce --create --alive --name "$(USER)'s SimpleEMR Cluster" \
	--num-instances ${CLUSTERSIZE} \
	--instance-type cc2.8xlarge | cut -d " " -f 4 > ./jobflowid
	@ echo "24 * (${CLUSTERSIZE} - 1)" | bc  > ./numberOfMappers

createhugeopt:
	@ echo creating EMR cluster
	${EMR} elastic-mapreduce --create --alive --name "$(USER)'s SimpleEMR Cluster" \
	--num-instances ${CLUSTERSIZE} \
	--bootstrap-action s3://elasticmapreduce/bootstrap-actions/configure-hadoop --bootstrap-name "configure task slots" --args "-s,mapred.child.java.opts=-Xmx512m,-s,mapred.tasktracker.map.tasks.maximum=48" \
	--instance-type cc2.8xlarge | cut -d " " -f 4 > ./jobflowid
	@ echo "48 * (${CLUSTERSIZE} - 1)" | bc  > ./numberOfMappers

submitjob: 
	${EMR} -j `cat ./jobflowid` --jar s3://$(USER).simple.emr/SimpleEMR-0.1.0-job.jar --arg s3://com.amazon.karan.ebstest/nt2.fs --arg s3://$(USER).simple.emr/output


submitoptimaljob: 
	n=`cat ./numberOfMappers`; s=`echo 39517434184/\($$n*3\) | bc`; ${EMR} -j `cat ./jobflowid` --jar s3://$(USER).simple.emr/SimpleEMR-0.1.0-job.jar --arg -Dmapred.max.split.size=$$s --arg -Dmapred.min.split.size=$$s --arg s3://com.amazon.karan.ebstest/nt2.snappy --arg s3://$(USER).simple.emr/output.opt

submithdfsjob: 
	n=`cat ./numberOfMappers`; s=`echo 39517434184/\($$n*3\) | bc`; ${EMR} -j `cat ./jobflowid` --jar s3://$(USER).simple.emr/SimpleEMR-0.1.0-job.jar --arg -Dmapred.max.split.size=$$s --arg -Dmapred.min.split.size=$$s --arg hdfs:////nt2.fs --arg s3://$(USER).simple.emr/output.hdfs


#
# logs:  use this to see output of jobs
#

logs: 
	${EMR} -j `cat ./jobflowid` --logs


#
# ssh: quick wrapper to ssh into the master node of the cluster
#
ssh:
	j=`cat ./jobflowid`; h=`${EMR} --describe -j $$j | grep "MasterPublicDnsName" | cut -d "\"" -f 4`; echo "h=$$h"; if [ -z "$$h" ]; then echo "master not provisioned"; exit 1; fi
	j=`cat ./jobflowid`; h=`${EMR} --describe $$j | grep "MasterPublicDnsName" | cut -d "\"" -f 4`; ssh -L 9100:localhost:9100 -i ${KEYPATH} hadoop@$$h

# 
# sshproxy: ssh -L 9100:localhost:9100 -i /Users/karanb/.ssh/normal.pem hadoop@ec2-50-17-170-26.compute-1.amazonaws.com
# don't know how to automate this
#
sshproxy:


