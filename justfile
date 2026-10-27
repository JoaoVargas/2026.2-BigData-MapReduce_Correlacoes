java_home := env_var_or_default("JAVA_HOME", "/usr/lib/jvm/java-17-openjdk")
hadoop_root := env_var_or_default("HADOOP_ROOT", "/tmp/map-reduce-hadoop-run")
streaming_jar := env_var_or_default("HADOOP_STREAMING_JAR", "/usr/share/hadoop/tools/lib/hadoop-streaming-3.5.0.jar")

default:
    @just --list

# Builds release binaries
build:
    cargo build --release --bins

# Debugs pipeline without Hadoop; not valid as final delivery execution
debug-local: build
    cat data/input.csv | target/release/mapper | target/release/combiner | target/release/reducer

# Sends complete input file to HDFS
hdfs-upload:
    JAVA_HOME={{java_home}} hdfs dfs -mkdir -p "{{hadoop_root}}/input"
    JAVA_HOME={{java_home}} hdfs dfs -put -f data/input.csv "{{hadoop_root}}/input/input.csv"

# Runs mandatory Hadoop Streaming pipeline; replaces only prior job output
run: hdfs-upload build
    JAVA_HOME={{java_home}} hdfs dfs -rm -r -f "{{hadoop_root}}/output"
    JAVA_HOME={{java_home}} hadoop jar "{{streaming_jar}}" -files target/release/mapper,target/release/combiner,target/release/reducer -input "{{hadoop_root}}/input" -output "{{hadoop_root}}/output" -mapper mapper -combiner combiner -reducer reducer

# Shows Hadoop job output after job creates output directory
hdfs-output:
    JAVA_HOME={{java_home}} hdfs dfs -cat "{{hadoop_root}}/output/part-*"
