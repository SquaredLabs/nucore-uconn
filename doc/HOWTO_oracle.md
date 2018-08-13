# Running Oracle in Development

Follow these instructions to set up the Oracle database to run in Docker, but the app itself in your native environment.

## Setting up the Oracle Server with Docker

### Set up Docker and Docker Hub

1. Install Docker for Mac by running `brew cask install docker`
1. Sign up for a Docker Hub account at https://hub.docker.com/. If you already have a Docker Hub account, you can skip this step and use your existing account.
1. Go to https://store.docker.com/images/oracle-database-enterprise-edition and click the button **Proceed to Checkout**. Complete and submit the form in order to get access to the free container that Oracle provides.
1. In your terminal, make sure that you are logged in with your Docker Hub credentials by running `docker login`.

### Start an Oracle container

```
mkdir $HOME/oracle_data
docker run -p 1521:1521 --name nucore_db -v $HOME/oracle_data:/u01/app/oracle sath89/oracle-12c
# This will take several minutes as the database initializes.
# Wait for "Database ready to use. Enjoy! ;)"
```

`$HOME/oracle_data` is just a recommended location where your oracle data files will
be saved. This will allow them to remain persistent even across re-creations of
the container.

* Next time you want to start the server, run:

```
docker start nucore_db
# wait, it sometimes takes a few minutes to come up
# "ORA-01033: ORACLE initialization or shutdown in progress" means wait.
```

The next time you need the database, start it just by running:

```
docker start --interactive oracle
```

## Setting up the Oracle Client Drivers

### Install Oracle Instant Client

1. Enable the homebrew tap for Oracle Instant Client by running `brew tap InstantClientTap/instantclient`.
1. Run each of these commands, following the displayed instructions for how to download the appropriate .zip files from Oracle’s website. After you download the files and place them in Homebrew’s cache directory, brew will take care of the rest:
    ```
    brew install instantclient-basic
    brew install instantclient-sqlplus
    brew install instantclient-sdk
    ```

### Set Up Environment Variables

1. Add to `~/.profile` (bash) or `~/.zprofile` (zsh)

```
# The Oracle adapter for ActiveRecord uses this password to connect as a
# system user, to be able to create and drop databases appropriately.
export ORACLE_SYSTEM_PASSWORD=Oradoc_db1

# This is used to specify the default language and encoding for Oracle clients
export NLS_LANG="AMERICAN_AMERICA.UTF8"
```

1. `source ~/.profile` or `source ~/.zprofile`, to load the changes you just made


### Test Your Installation

To connect to the Oracle server, run:

```
sqlplus "sys/Oradoc_db1@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=localhost)(PORT=1521))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=ORCLCDB.localdomain)))" as sysdba
```

Your output should show something like this:

```
Connected to:
Oracle Database 12c Enterprise Edition Release 12.2.0.1.0 - 64bit Production

SQL> 
```

## Setting up the Database

1. Make sure you have the `activerecord-oracle_enhanced-adapter` and `ruby-oci8` gems enabled in your `Gemfile`.
1. Copy the Oracle template for `database.yml` by running `cp config/database.yml.oracle.template config/database.yml`.
1. Run `bundle exec rake db:setup`.
1. Optionally, run `bundle exec rake demo:seed` if you want to populate the database with demo data.

# Optional Extras

## Install Oracle SQL Developer

* Download from: `http://www.oracle.com/technetwork/developer-tools/sql-developer/overview/index.html`

* Install into `/Applications`

## Restore From Backup

1. Run `bundle exec rake db:drop db:create`. This will ensure that your database exists, and that it is empty. Without this step, the import may skip tables which already exist, and it may fail if the database does not exist.

1. Copy the `.dmp` file to `oracle/u01/app/oracle/admin/ORCL/dpdump/` (assuming you are using `oracle/` as the data directory, per above), so it is located in the server’s default data pump directory.

1. Start a bash shell in the `oracle` container:

    ```
    docker exec \
      --interactive \
      --tty \
      oracle \
      bash
    ```

1. Run the following command to ensure that the file you copied is available in the `DATA_PUMP_LOCATION` configured on the server:

    ````
    ln -fsn /ORCL/u01/app/oracle/admin /u01/app/oracle/admin
    ````

  This only needs to be done once, but if you’re having trouble, rerun it.

1. Import the dump, replacing DUMPFILE with the name of your dump file, and REMAP_SCHEMA with your database’s username if necessary:

* Install into `/Applications`

#### Restore from a backup

Run `bundle exec rake db:oracle_drop_severe`. This will ensure that your database
is clean. Without it the import might skip tables due to them already existing.

Assuming you used `$HOME/oracle_data` as the volume location when you did `docker run`:

Copy the `.dmp` file to `$HOME/oracle_data/admin/xe/dpdump/`

Get a bash shell inside your container:

```
docker exec -it nucore_db bash
```

Run this (replacing the DUMPFILE filename and the second part of REMAP_SCHEMA with your database's username):
```
impdp system/oracle@//localhost:1521/xe DIRECTORY=data_pump_dir DUMPFILE=expdp_schema_COR1PRD_201708191913.dmp REMAP_SCHEMA=bc_nucore:nucore_nu_development
```
