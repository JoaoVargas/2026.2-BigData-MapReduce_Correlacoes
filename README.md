# map-reduce

Pipeline MapReduce (mapper/combiner/reducer) escrito em Rust, compatível com o protocolo do Hadoop Streaming, que calcula a **correlação de Pearson entre a temperatura e as demais variáveis** do dataset Forest Fires (Montesinho).

## Como funciona

- **`src/lib.rs`** — struct `Stats`, que acumula média, variância e covariância parciais usando o algoritmo online de Welford. `Stats::merge` une estados de partições diferentes sem perder precisão, o que permite calcular Pearson de forma distribuída (map → combine → reduce).
- **`src/bin/mapper.rs`** — lê `data/input.csv` linha a linha e emite, para cada registro, um par `(chave, Stats::single(temp, valor))` por variável numérica (`x`, `y`, `ffmc`, `dmc`, `dc`, `isi`, `rh`, `wind`, `rain`, `area`, e `temp` consigo mesma como controle) e indicadores one-hot para mês (`month_jan`...`month_dec`) e dia da semana (`day_mon`...`day_sun`).
- **`src/bin/combiner.rs`** — funde estados da mesma chave localmente, reduzindo volume transferido no shuffle.
- **`src/bin/reducer.rs`** — funde os estados finais por chave, calcula Pearson e classifica a força/sinal da correlação. A chave `temp` (autocorrelação) é removida da saída final e logada em stderr só como sanity check.

## Rodar localmente (sem Hadoop)

Pré-requisito: Rust/Cargo instalado.

```bash
just build
just debug-local
```

Isso builda os binários em release e roda `cat data/input.csv | mapper | combiner | reducer`, imprimindo no stdout uma linha por variável: `chave  r=valor  n=contagem  classificação`.

> `debug-local` existe só para depuração rápida — a entrega final do TDE é a execução via Hadoop Streaming (target `run`).

## Rodar com Hadoop (modo local, sem HDFS/YARN)

A forma mais simples de executar de fato via Hadoop é o **modo local** do framework (`LocalJobRunner`), que é o padrão quando `core-site.xml`/`yarn-site.xml` não são configurados. Isso roda o job real via `hadoop jar ... streaming`, sem precisar formatar NameNode, subir daemons HDFS/YARN nem configurar SSH.

### 1. Obter o Hadoop

Baixe e extraia uma distribuição do Hadoop (ex.: 3.5.0) dentro de `hadoop/`:

```bash
curl -L -o hadoop/hadoop-3.5.0.tar.gz \
  https://dlcdn.apache.org/hadoop/common/hadoop-3.5.0/hadoop-3.5.0.tar.gz
tar -xzf hadoop/hadoop-3.5.0.tar.gz -C hadoop
```

### 2. Exportar variáveis de ambiente

```bash
export JAVA_HOME="$HOME/.jenv/versions/17"   # qualquer JDK 17+
export HADOOP_HOME="$PWD/hadoop/hadoop-3.5.0"
export PATH="$HADOOP_HOME/bin:$PATH"
export HADOOP_ROOT="$PWD/hadoop/forest-fires-data"   # pasta local de trabalho do job
export HADOOP_STREAMING_JAR="$HADOOP_HOME/share/hadoop/tools/lib/hadoop-streaming-3.5.0.jar"
```

`HADOOP_ROOT` e `HADOOP_STREAMING_JAR` são lidos pelo `justfile` (`hadoop_root` e `streaming_jar`); sem essas variáveis, caem nos defaults `/tmp/map-reduce-hadoop-run` e `/usr/share/hadoop/tools/lib/hadoop-streaming-3.5.0.jar`.

### 3. Rodar o pipeline

```bash
just run
```

Esse target já builda os binários, sobe `data/input.csv` para `$HADOOP_ROOT/input` (no modo local isso é só uma cópia em disco, não HDFS real), remove um output anterior se existir, e submete o job:

```
hadoop jar $HADOOP_STREAMING_JAR -files target/release/mapper,target/release/combiner,target/release/reducer \
  -input $HADOOP_ROOT/input -output $HADOOP_ROOT/output \
  -mapper mapper -combiner combiner -reducer reducer
```

### 4. Ver o resultado

```bash
just hdfs-output
```

Imprime `$HADOOP_ROOT/output/part-*`.

### Rodando de novo

`just run` já remove `$HADOOP_ROOT/output` antes de submeter, então pode ser chamado repetidamente sem limpeza manual.
