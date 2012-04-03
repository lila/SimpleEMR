# Makefile for SimpleEMR

#
# commands setup (ADJUST THESE IF NEEDED)
# 
S3CMD                   = s3cmd
EMR			= elastic-mapreduce
CLUSTERSIZE		= 10
REGION                  = us-east
KEY			= normal


# 
# make targets 
#

help:
	@echo "help for Makefile for SimpleEMR sample project"
	@echo "make create - create an EMR Cluster"
	@echo "make destroy - clean up everything"

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


createhuge: jobflowid
	@ echo creating EMR cluster
	${EMR} elastic-mapreduce --create --alive --name "$(USER)'s SimpleEMR Cluster" \
	--num-instances ${CLUSTERSIZE} \
	--instance-type cc2.8xlarge | cut -d " " -f 4 > ./jobflowid
	@ echo "24 * (${CLUSTERSIZE} - 1)" | bc  > ./numberOfMappers

createhugeopt:


submitjob: bootstrap
	${EMR} -j `cat ./jobflowid` --jar s3://$(USER).simple.emr/SimpleEMR-0.1.0-job.jar --arg s3://com.amazon.karan.ebstest/nt2.fs --arg s3://$(USER).simple.emr/output


submitoptimaljob: bootstrap
	n=`cat ./numberOfMappers`; s=`echo 39517434184/\($$n*3\) | bc`; ${EMR} -j `cat ./jobflowid` --jar s3://$(USER).simple.emr/SimpleEMR-0.1.0-job.jar --arg -Dmapred.max.split.size=$$s --arg -Dmapred.min.split.size=$$s --arg s3://com.amazon.karan.ebstest/nt2.fs --arg s3://$(USER).simple.emr/output.opt



#
# logs:  use this to see output of jobs
#

logs: 
	${EMR} -j `cat ./jobflowid` --logs


#
# ssh: quick wrapper to ssh into the master node of the cluster
#
ssh:
	${EMR} -j `cat ./jobflowid` --ssh



