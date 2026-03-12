# Java Remote Debugging for PH-EE Components

This guide explains how to attach a Java debugger (VS Code, IntelliJ IDEA, or `jdb`) to any Payment Hub EE connector pod running in a local Gazelle Kubernetes cluster.

---

## Prerequisites

- A running Gazelle cluster with PH-EE deployed
- `kubectl` configured and pointing at your cluster
- Java 17+ installed locally (for `jdb`)
- VS Code with the [Extension Pack for Java](https://marketplace.visualstudio.com/items?itemName=vscjava.vscode-java-pack) installed, **or** IntelliJ IDEA

---

## How it works

The Java Debug Wire Protocol (JDWP) agent runs inside the container and listens on a TCP port. Because the agent is inside a pod, it cannot be reached directly. `kubectl port-forward` creates a tunnel from a local port on your workstation to the pod's JDWP port. Your IDE connects to the local end of that tunnel.

```
Your IDE  ──(localhost:5010)──►  kubectl port-forward  ──►  pod:5010 (JDWP agent)
```

---

## Step 1 — Deploy with the debug overrides

A ready-made Helm override file lives at `config/ph_values_debug.yaml`. Apply it on top of the base values:

```bash
helm upgrade ph-ee-engine ph-ee-engine/ph-ee-engine \
  -f config/ph_values.yaml \
  -f config/ph_values_debug.yaml \
  -n paymenthub
```

This enables the JDWP agent on every PH-EE connector with `suspend=n` — the JVM starts normally and the debugger can attach at any time without blocking startup.

> **To debug a startup failure**, change `suspend=n` to `suspend=y` for the target component in `ph_values_debug.yaml`. The JVM will pause before executing any application code and wait for the debugger to connect before proceeding.

---

## Step 2 — Verify the agent started

Check that the pod logged the JDWP listening message:

```bash
kubectl logs -n paymenthub deploy/ph-ee-operations-app | grep -i jdwp
# Expected output:
# Listening for transport dt_socket at address: 5010
```

If the line is absent, the JDWP agent was not loaded. Confirm `JAVA_TOOL_OPTIONS` is set correctly:

```bash
kubectl exec -n paymenthub deploy/ph-ee-operations-app -- env | grep JAVA_TOOL_OPTIONS
```

---

## Step 3 — Open a port-forward tunnel

Open a terminal and keep it running for the duration of your debug session.

| Component | Pod debug port | Command |
|---|---|---|
| `operations_app` | 5010 | `kubectl port-forward -n paymenthub deploy/ph-ee-operations-app 5010:5010` |
| `ph_ee_connector_ams_mifos` | 5011 | `kubectl port-forward -n paymenthub deploy/ph-ee-connector-ams-mifos 5011:5011` |
| `ph_ee_bulk_processor` | 5012 | `kubectl port-forward -n paymenthub deploy/ph-ee-bulk-processor 5012:5012` |
| `channel` | 5013 | `kubectl port-forward -n paymenthub deploy/ph-ee-connector-channel 5013:5013` |
| `ph_ee_connector_mojaloop` | 5014 | `kubectl port-forward -n paymenthub deploy/ph-ee-connector-mojaloop-java 5014:5014` |
| `zeebe_ops` | 5015 | `kubectl port-forward -n paymenthub deploy/ph-ee-zeebe-ops 5015:5015` |
| `ph_ee_connector_bulk` | 5016 | `kubectl port-forward -n paymenthub deploy/ph-ee-connector-bulk 5016:5016` |
| `importer_rdbms` | 5017 | `kubectl port-forward -n paymenthub deploy/ph-ee-importer-rdbms 5017:5017` |

You can forward multiple components at once by running each command in a separate terminal.

---

## Step 4 — Attach your debugger

### VS Code

1. Open the connector's source project in VS Code.
2. Go to **Run and Debug** (`Ctrl+Shift+D`) → **create a launch.json file** → select **Java**.
3. Add the following configuration to `.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "java",
      "name": "Attach to operations-app (pod)",
      "request": "attach",
      "hostName": "localhost",
      "port": 5010,
      "projectName": "ph-ee-operations-app"
    }
  ]
}
```

Replace `port` with the port for your target component (see table above) and set `projectName` to match the Gradle project name.

4. With the port-forward tunnel open, click **Start Debugging** (F5). VS Code will connect, and breakpoints set in the source will be hit when the relevant code executes inside the pod.

### IntelliJ IDEA

1. Open **Run → Edit Configurations** → click **+** → **Remote JVM Debug**.
2. Set:
   - **Host**: `localhost`
   - **Port**: the port for your target component (e.g. `5010`)
   - **Debugger mode**: `Attach to remote JVM`
3. Click **OK**, then run the configuration. IntelliJ will connect to the pod.

### jdb (command line)

```bash
# Attach to operations_app (port 5010)
jdb -attach localhost:5010 -sourcepath /path/to/ph-ee-operations-app/src/main/java

# Once connected, set a breakpoint and resume:
stop in org.mifos.connector.example.ExampleRoute.configure
run
```

---

## Why `address=*:PORT`, not `address=localhost:PORT`

The original issue used `address=localhost:5010`. This binds the JDWP socket only to the loopback interface inside the container. Depending on the pod's network stack and CNI plugin, `localhost` may resolve to `::1` (IPv6 loopback) or `127.0.0.1` (IPv4 loopback). If the JVM binds to `::1` but `kubectl port-forward` connects over IPv4 (or vice versa), the tunnel connects but the debugger handshake fails silently — you can see the stack but not variables or breakpoints.

`address=*:PORT` explicitly binds to all available interfaces (both IPv4 and IPv6), which is the documented pattern for any scenario involving a forwarded TCP tunnel.

---

## Why JAVA_TOOL_OPTIONS is written as a single-line string

The original snippet used a YAML literal block scalar (`|`) for `JAVA_TOOL_OPTIONS`, which embeds newline characters into the environment variable. While modern JVMs accept newlines as whitespace separators, some JVM versions and init systems silently truncate the variable at the first newline, meaning only `-Xms128m` is ever processed and the `-agentlib` line is never reached.

Using a plain single-line string eliminates this class of failure entirely.

---

## Why variables may not appear (connector build issue)

By default, `javac` only emits line number and source file debug attributes. It does **not** emit local variable name metadata unless explicitly requested. Without variable metadata, a debugger can show the stack trace and step through lines, but cannot display variable values.

To enable full debug symbols, the connector's `build.gradle` must include:

```groovy
tasks.withType(JavaCompile).configureEach {
    options.compilerArgs += ['-g:source,lines,vars']
}
```

This flag is already present in the `mifos-connector-starter-template`. Connectors that have been migrated using the starter template will have full variable inspection. Connectors that have not yet been migrated may show only stack frames until this flag is added to their build.

---

## Troubleshooting

**Port-forward exits immediately**

The pod may not be running. Check:
```bash
kubectl get pods -n paymenthub
kubectl describe pod -n paymenthub <pod-name>
```

**"Connection refused" on attach**

The JDWP agent did not start. Verify `JAVA_TOOL_OPTIONS` is set in the pod environment:
```bash
kubectl exec -n paymenthub deploy/<deployment-name> -- env | grep JAVA_TOOL_OPTIONS
```

Also check the pod log for the `Listening for transport dt_socket` line (Step 2).

**Debugger connects but breakpoints are not hit**

Ensure you have the source code open in your IDE that matches the exact version of the running container image. A mismatch between source and bytecode prevents breakpoints from binding.

**Stack shows but variables are empty**

The connector was not compiled with `-g:source,lines,vars`. See the section above. If you cannot rebuild the connector image, you are limited to stack-only debugging until the image is rebuilt with the flag.

**`suspend=y` — pod stuck in `Running` but app never starts**

The JVM is waiting for a debugger to attach. Attach your IDE (Step 4) to resume execution.
