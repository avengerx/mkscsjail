# mkscsjail

This cumbersome script sets up a (hopefully) secure American Truck Simulator (ATS) or Euro Truck Simulator 2 (ETS2) dedicated server in a linux system.

## Disclaimer

This script requires root privileges to run, I cannot be held responsible for any damage this can incur to your system. It works for me and I can offer no warranty whatsoever it is going to work on other linux distributions, versions, or platforms.

The tested system is a Gentoo v17.0 (obsolete) profile.

## Some features include

- Minimalistic `chroot()` jail by copying required solibs reported by the executables and some extras that `ldd` doesn't report for some reason.
- Allows to bind the server to a specific IP address (although the dedicated server software don't offer this option, requires `gcc` to compile wrappers during deploy)
- Allows to bind the server to specific physical CPUs (requires `numactl` and `NUMA` support in kernel)
- Simple but hopefully useful interface to set up the server's configuration file (can load an existing config file to preload settings)
- Some instructions to common required steps, like generating the server_packages.* files
- Prepares scripts to easily update the game (and steam client) and to run the server itself with limited user accounts -- one for updating games, another for running the server)

## Prerequisites

- Linux
- The `chroot` tool (from GNU coreutils)
- Root access (chroot requires root to run, although the game and update will be run by a limited user
- A legitimate copy of the dedicated server's respective SCS game (to create the `server_packages.*` files) [official documentation](https://modding.scssoft.com/wiki/Documentation/Tools/Dedicated_Server#How_to_export_server_packages)
- Updater and Runner user accounts (see "creating users" section below)

### Optional prerequisites

- `numactl` tool to enable CPU selection support (https://github.com/numactl/numactl)
- `gcc` compiler to enable building of the IP binding wrapper
- `iproute2` to allow enumerating IP addresses, when configuring IP binding
- A Steam Game Server Account for the respective game to allow persistent server ID (docs says games may run without this, but I didn't test; so the script will allow it to be empty)

### Creating users

Currently the script does not support choosing custom users (pending feature!), and does not create the users as well. If the users don't exist or don't fit a given requirement, the script shall fail in its early stages.

The user accounts the script currently relies on are:
- **updater:** `scsup` (will the one running `steamcmd` to update the game files)
- **runner:** `scsrun` (will be the one running the actual dedicated server)

Both users should share the same group:
- **group:** `scs`

If you really want to name them something else, edit lines 12 (`u_upd`) and 13 (`u_run`) of the script with the desired user names. As long as they are different users (different user name for each) and belong to the same group, the script should work fine. The group is defined in the script's line 13 (`u_grp`)

An example command to create the group and users would be:

```bash
# groupadd scs
# useradd -c "SCS Dedicated Servers Runner" -g scs -d /tmp -s /bin/false scsrun
# useradd -c "SCS Dedicated Servers Updater" -g scs -d /tmp -s /bin/false scsup
```

The commands below should complain about `-d` pointing to the existing `/tmp` directory, but precisely for this reason, it won't create any home directory for the users. They don't need a home directory within the server at all, as they are supposed to be running within the jail. Having an usual home directory or even being able to log on (`/bin/sh` shell) shouldn't affect how the users work (but potentially allow undesired access to the server). These users are useless per se, as they are not able to call chroot() at all, unless the server admin meticulously set them up to be able to.

One case where these users may be able to log would be if they're given very strick root (sudo) access to the updater/runner scripts respectively so as to allow, for instance, non-administrator users to run the game server. This kind of configuration is outside the scope of this script. It simply sets up the jail, and the scripts must be run as a priviliged user.

## The Server Packages files

The `server_packages.sii` and  `server_packages.dat` need to be known when the server is set up. The script will require them to make the whole process a build-and-run experience.

The script will look for the Server Packages files:
- In the current directory if only one game server is chosen
- In the game's respective subdirectory, `ats/` and `ets2/` if both games are selected -or- if not present in current directory.

The path to the files can be specified with `--server-packages=/path/to`.

A basic check-up for the file's validity (if it belongs to the selected game) is performed to ensure the right files are in place before all the process starts.

See [SCS official documentation on Server Packages](https://modding.scssoft.com/wiki/Documentation/Tools/Dedicated_Server#How_to_export_server_packages) to make sure you have them right. Beware the file carries loaded mods information so anyone joining the server would either:

- have the same mods you have
- you enabled **Optional mods** (`m`) _and_ your mods are properly configured as optional in their mainifests
- you disable any mods you don't want the server to require before doing the steps to generate the `server_packages` files.

The `server_packages` files also carries on information about what DLCs you have installed. So if you only have a few DLCs, other people with all DLC will probably have the DLCs deactivated when joining your server.

You may ask your friend who has all DLCs to create the files for you. Files generated on the game in any platform (Windows, Linux, Mac) should work for the dedicated server.

## Running the script

To run the script, simply call it:

```bash
# ./mkscsjail.sh
```

If you have the `server_packages.*` files in `ats/` and `ets2/` directories, it will then show the following configuration dialogs to confirm settings and proceed with the jail set up.

By default it will set up a jail for both American Truck Simulator (ATS) and Euro Truck Simulator 2 (ETS2) dedicated servers. If just one of them is desired (and it should save ~800MB on downloads), select with either `--ats` or `--ets2` arguments:

```bash
# ./mkscsjail.sh --ats
```

If you're running as a normal user, it may suffice to just run under sudo:

```bash
$ sudo ./mkscsjail.sh --ats
```

It would be a good idea though, to place the jail outside the user home, as it will create files owned by root:

```bash
$ sudo ./mkscsjail.sh --ats --jaildir=/var/lib/atsd-jail
```

## Script flow

Once the script starts it first processes all commandline arguments, overwriting its internal defaults with whatever is provided (see **Commandline arguments** below).

Then it will perform some checks for available pre-requisites and commandline arguments consistency (like disabling IP binding if `gcc` is not found).

```
Checking for server_packages: ok.
Checking for base solibs: ok.
Checking runner/updater users: ok.
Checking whether we have locale archives: ok, /usr/lib64/locale/locale-archive.
Checking whether we have root SSL certificates: ok, /etc/ssl/certs/.
```

Once all is right, it will show the current overall `chroot()` jail configuration, with options to adjust the settings:

```
Jail configuration:
a) Jail path: ./scsjail
b) Bind to: No IP binding configured.
c) NUMA bindings: disabled.

x) Accept changes and continue script execution.
z) Aborts/quits without changes.
```

This is the moment NUMA CPU and IP binding is set up. Use `x` to confirm the configuration when done, and the script will proceed to configure the server.

```
Current game configuration:
                 Game: ATS
          Server name: a)chRoot-jailed Dedicated Server
   Server description: b)This server was set up using mkscsjail.sh
      Welcome message: c)Be polite and respectful to fellow truckers.
             Password: d)<no password>
   Server Login Token: e)none (non-persistent server id)
 Time zone simulation: f)enabled - show also current time zone
     Maximum vehicles: g)160 (server total)
Controllable vehicles: h)80 (per player, up to max)
   Spawnable vehicles: i)20 (per player, up to max)
          Server port: j)27015 (connection), 27016 (query)
  Server virtual port: k)100 (connection), 101 (query)
[ ] l)Force Speed Limiter
[x] m)Optional mods                    [x] n)Damage from players
[ ] o)Collisions disabled in service   [ ] p)Collisions disabled when in menu
[ ] q)Hide players in companies' area  [ ] r)Show player name tags in trucks
[x] s)Enable AI traffic                [x] t)Hide teleported colliders

:: (u) No moderator set up.

x) Accept changes and continue script execution.
z) Aborts/quits without changes.
```

Here all server settings can be configured.

- In case both ATS and ETS2 games are to be set up, some settings will allow (or require) individual configuration.
- Some server info like the name, description, password and most togglable settings are carried to both games.
- The **Server Login Token** uses Steam Game Server accounts which are tied to the specific Steam game, so each game will have its own token (instructions are shown upon selecting the option in the script).
- The **Force Speed Limiter** toggle is, by default, disabled for ATS and enabled for ETS2, following regional regulations. This particular setting -can- be the same on both servers.
- The **Server Port** used when only one game is selected will be `port` for connection and `port + 1` for query (e.g. `27000`, `27001`). If both gamers are to be set up, then ATS will get `port`, `port + 1`, and ETS2 `port + 2` and `port + 3` for connection and query, respectively.

#### Down to this point no change would have been made to the system

When done, hit `x` to begin the actual jail configuration. Next, the script should output the progress with something like:

```
Creating chroot() jail: mkdir, symlinks, solibs, bindip, dev, locale, SSL certs, steamcmd, config, server_packages, scripts, done.
Mounting proc filesystem: /opt/atsdjail/proc, done.
```

This should run pretty fast as the tasks are not really complex. But then it should "hang" in the following line(s) for several minutes, depending on the game setup configuration:

```
Updating American Truck Simulator: steam request re-run, steam request re-run, done.
```

In that step, the script would run steam client, already in the jail environment, as the limited "updater" user to self-update the `steamcmd` client, and install the game(s) to their latest updated version. This will sum up to 800MB download per game.

This is the same script you would run when you want to check for dedicated server updates. It doesn't check if the server is running and won't kill it if so; the update should work if the server is running but once updated, the server needs to be manually restarted in order to apply the update.

When all t his is done, the script will perform its last deploy steps.

```
Unmounting /opt/atsdjail/proc: done.
Deploying server solibs: done.
```

These steps are still required in order to be able to start the server, so if the process is interrupted at update, the whole script should be re-run. You may safely erase the jail directory in an incomplete run.

And then finally the script presents with the commands to run to update/run the server.

```
Jail configured successfully at: scsjail

To run the game server:
# scsjail/run.sh

To check for game updates:
# scsjail/update.sh
```

The paths shown are relative to the current directory and affected by what was entered with the `--jaildir=` commandline argument.

## Configuration files

The configuration files are deployed to a directory owned by the runner user (default `scsrun`) within the jail's `var/lib/` and, respectively for ATS and ETS2, `American Truck Simulator` and `Euro Truck Simulator 2`.

So suppose you've run `./mkscsjail.sh --jaildir=/opt/atsjail --ats`, ATS' `server_config.sii` will be in `/opt/atsjail/var/lib/American Truck Simulator/server_config.sii`.

## Commandline arguments

This is simply a dump of `./mkscsjail.sh --help`, for quick reference:

```
usage: ./mkscsjail.sh <flags> <server-parameters>

Flags:
  --jaildir=[path]
    Directory where to set up the jail files in. If the directory doesn't
    exist, it will be created.
    Default: ./scsjail

  --bind=<ip:interface>
    Binds the server to the specific IP address and interface.
    Format: x.y.z.k nic0
    E.g.: 192.168.0.2:eth0
    Default: any (bind to all IPs in all interfaces)

  --numa-cpu=<physical cpu>
    Binds the server to specific physical CPU.
    Default: empty (disable NUMA).
    If you specify this, the CPU cores must be specified via --numa-cores.

  --numa-cores=<CPU cores index interval>
    Binds the server to specific CPU cores in the selected physical CPUs.
    Example: --numa-cores=14-17,34-37
    Default: empty (disable NUMA).
    If you specify this, the physical CPUs must be specified via --numa-cpus.

  --game=[ats|ets2|both]
    Specifies which game to set up in the jail; either American Truck
    Simulator or Euro Truck Simulator 2; or just both games.
    Overrides any --both, --ets or --ats specified previously.
    Default: both

  --ats, --amtrucks
    Specifies American Truck Simulator only should be set up in the jail.
    Overrides any --both, --ets or --game specified previously.

  --ets, --ets2, --eutrucks
    Specifies Euro Truck Simulator 2 only should be set up in the jail.
    Overrides any --both, --ats or --game specified previously.

  --both, --bothgames
    Specifies both games should be set up in the jail.
    Overrides any --ets, --ats or --game specified previously.

  --server-packages=<path>
  --sp=<path>
    Path to the server_packages.{dat,sii} files required to run the server.
    More information about server packages files at:
    https://modding.scssoft.com/wiki/Documentation/Tools/Dedicated_Server

  --server-packages-path=<path>
    Path to search for game's server_packages.sii and server_packages.dat.
    Will search in own directory if only either game is selected or,
    respectively, inside ats/ and ets2/ if not found or if both games are to
    be set up. Information on how to generate the files at:
    https://modding.scssoft.com/wiki/Documentation/Tools/Dedicated_Server

Server Parameters:
    Server parameters will be shared by both games if both are set up in the
    jail except, by default, the speed limiter is disabled
    for ATS and enabled for ETS2.

  --load-config=<path>
  --lc=<path>
    Loads intial server configuration parameters from .sii file.
    This will override any server parameter passed before in the command line.

  --sv-desc=<description>
  --svd=<description>
    Server's description. Maximum length: 63 characters.
    Default: This server was set up using mkscsjail.sh

  --sv-name=<name>
  --svn=<name>
    Server name in lobby listing. Maximum length: 63 characters.
    Default: chRoot-jailed Dedicated Server

  --sv-welcome=<message>
  --svw=<message>
    Server welcome message. Maximum length: 127 characters.
    Default: Be polite and respectful to fellow truckers.

  --sv-pass=[password]
  --svpw=[password]
    Server password. Empty for no password. Maximum 63 characters.
    Default: empty (no password).

  --sv-port=<1025-65535>
  --svpt=<1025-65535>
    Server base port. Default is 27015 and it will also allocate the next
    port for the query. E.g. if you choose 12300 as the port, 12301 will
    be assigned to the server query listening socket.
    Default: 27015

  --sv-virtual-port=<value>
  --svcvp=<value>
    Server virtual base port. Similarly to --sv-port, the query port will
    be this value + 1.
    Default: 100

  --sv-logon-token=[steam server logon token]
  --svlt=[steam server logon token]
    Steam game server account's login token, created at:
    https://steamcommunity.com/dev/managegameservers
    Your steam account need not to be limited in order to create one,
    and you must use the _game_ App Id (ats=270880, ets2=227300)
    corresponding to the game server when registering the token.
    If installing both games, use [ats,ets2] comma-separated values
    to provide both tokens. Empty may work by creating non-persistent
    server Id, but it may not work as well.

  --sv-modlist=[comma-separated list of Steam IDs]
  --svml=[comma-separated list of Steam IDs]
    List of Steam ID of game moderators. Game moderators can kick, ban
    change the welcome message, rain probability and time of day.
    Default: empty

  --sv-player-damage=<true|false>
  --svpd=<true|false>
    Whether players can receive damage from other players' collisions.
    Default: true

  --sv-traffic=<true|false>
  --svt=<true|false>
    Whether AI traffic in game is enabled.
    Default: true

  --sv-hide-in-companies=<true|false>
  --svhic=<true|false>
    Hide players whilst within company patios.
    Default: false

  --sv-service-no-collision=<true|false>
  --svsnc=<true|false>
    Disable collisions for players in service shops.
    Default: false

  --sv-menu-no-collision=<true|false>
  --svmnc=<true|false>
    Disable collisions for players outside the game world
    (in menu, maps, jobs, also known as menu ghosting).
    Default: false

  --sv-hide-colliding=<true|false>
  --svhc=<true|false>
    Hide colliding vehicles after teleport.
    Default: true

  --sv-force-speedlim=<true|false>
  --svfs=<true|false>
    Force truck speed limiter regardless of user settings. If false, whatever
    the player sets up is allowed. If true, will enforce the game's speed
    limiter settings.
    Default: false,true (ats, ets2)

  --sv-optional-mods=<true|false>
  --svom=<true|false>
    Enable optional mods. If true, will not require players to have mods which
    manifest claims being optional. If false, all mods will be required to allow
    players to join.

  --sv-timezones=<0|1|2>, --svtz=<0|1|2>
    Set in-game time zone simulation. Not sure if this even works.
    Default: 2

  --sv-name-tags=<true|false>
  --svnt=<true|false>
    Whether to show player Steam names floating above their trucks.
    Default: false

  --sv-max-vehicles=<value>
  --svmv=<value>
    Maximum amount of vehicles overall in the server.
    Default: 160

  --sv-max-ai-vehicles-player=<value>
  --svmaivp=<value>
    Maximum number of a given player's AI vehicles.
    Default: 80

  --sv-max-ai-vehicles-player-spawn=<value>
  --svmavps=<value>
    Maximum amount of vehicles a player can spawn at a time.
    Default: 20
```
