# Robber

Dynamic instrumentation toolkit for developers, reverse-engineers, and security
researchers. Learn more at [robber.re](https://robber.re/).

Two ways to install
===================

## 1. Install from prebuilt binaries

This is the recommended way to get started. All you need to do is:

    pip install robber-tools # CLI tools
    pip install robber       # Python bindings
    npm install robber       # Node.js bindings

You may also download pre-built binaries for various operating systems from
Robber's [releases](https://github.com/robber/robber/releases) page on GitHub.

## 2. Build your own binaries

### Dependencies

For running the Robber CLI tools, e.g. `robber`, `robber-ls-devices`, `robber-ps`,
`robber-kill`, `robber-trace`, `robber-discover`, etc., you need Python plus a
few packages:

    pip install colorama prompt-toolkit pygments

### Linux

    make

### Apple OSes

First make a trusted code-signing certificate. You can use the guide at
https://sourceware.org/gdb/wiki/PermissionsDarwin in the sections
“Create a certificate in the System Keychain” and “Trust the certificate
for code signing”. You can use the name `robber-cert` instead of `gdb-cert`
if you'd like.

Next export the name of the created certificate to relevant environment
variables, and run `make`:

    export MACOS_CERTID=robber-cert
    export IOS_CERTID=robber-cert
    export WATCHOS_CERTID=robber-cert
    export TVOS_CERTID=robber-cert
    make

To ensure that macOS accepts the newly created certificate, restart the
`taskgated` daemon:

    sudo killall taskgated

### Windows

    robber.sln

(Requires Visual Studio 2022.)

See [https://robber.re/docs/building/](https://robber.re/docs/building/)
for details.

## Learn more

Have a look at our [documentation](https://robber.re/docs/home/).
