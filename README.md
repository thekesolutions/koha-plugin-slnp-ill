# Koha Interlibrary Loans SLNP backend

## About SLNP

SLNP (TM) (Simple Library Network Protocol) is a TCP network socket based protocol 
designed and introduced by the company Sisis Informationssysteme GmbH (later a part of OCLC) 
for their library management system SISIS-SunRise (TM).
This protocol supports the bussiness processes of libraries.
A subset of SLNP that enables the communication required for regional an national ILL (Inter Library Loan) processes
has been published by Sisis Informationssysteme GmbH as basis for 
connection of library management systems to ILL servers that use SLNP.
Sisis Informationssysteme GmbH / OCLC owns all rights to SLNP.
SLNP is a registered trademark of Sisis Informationssysteme GmbH / OCLC.

## Synopsis

This project involves three different pieces:

* A Koha plugin, that bundles the ILL backend and provides convenient ways to add configurations.
  _FIXME_: This should mention the upcoming `install` and `upgrade` tools.
* An ILL backend **SLNP** that provides provides a simple method to handle ILL requests that
  are initiated by a regional ILL server using the SLNP protocol.
* A daemon  The additional service 'ILLZFLServerKoha' runs as a daemon in the background managing
  the communication with the regional ILL server and inserting records in tables illrequests and
  illrequestattributes by calling the *create* method of _SLNP_.

The remaining features of this ILL backend are accessible via the standard ILL framework in the Koha staff interface.

## Installing

* Download this plugin from the [Deployments > Releases](https://gitlab.com/thekesolutions/plugins/slnp/koha-plugin-slnp-ill/-/releases) page.
* Point your `<backend_directory>` entry to your instance's plugin directory like this

```xml
<backend_directory>/var/lib/koha/<instance>/Koha/Illbackends</backend_directory>
```

```shell
export KOHA_INSTANCE=<the_name_of_your_Koha_instance>
export KOHA_CONF=/etc/koha/sites/$KOHA_INSTANCE/koha-conf.xml
export PERL5LIB=/usr/share/koha/lib
cd $PERL5LIB/Koha/Illbackends/SLNP/install
./install.pl
```

* Activate the Koha ILL framwork and ILL backends by enabling the 'ILLModule' system preference.
* Check the <interlibrary_loans> division in your koha-conf.xml.
* Copy the Net::Server::Fork configuration file '/usr/share/koha/lib/Koha/Illbackends/SLNP/ILLZFLServerKoha/conf/ILLZFLServerKoha.conf' into directory '/etc/koha/sites/{name-of-your-Koha-instance}/'.
* Adapt the Net::Server::Fork configuration file '/etc/koha/sites/{name-of-your-Koha-instance}/ILLZFLServerKoha.conf', otherwise ILLZFLServerKoha will not work.
* Copy the service script '/usr/share/koha/lib/Koha/Illbackends/SLNP/ILLZFLServerKoha/conf/koha-ILLZFLServerKoha' into directory '/etc/init.d'
* Register the service script '/etc/init.d/koha-ILLZFLServerKoha' by calling 'update-rc.d koha-ILLZFLServerKoha defaults'.
+ Now the service ILLZFLServerKoha may be started (or stopped) by calling '/etc/init.d/koha-ILLZFLServerKoha start (or stop)' or by 'service koha-ILLZFLServerKoha start (or stop)'.
* Call hierarchy: '/etc/init.d/koha-ILLZFLServerKoha' calls '/usr/share/koha/lib/Koha/Illbackends/SLNP/ILLZFLServerKoha/bin/koha-ILLZFLServerKoha.sh' that calls '/usr/share/koha/lib/Koha/Illbackends/SLNP/ILLZFLServerKoha/bin/runILLZFLServerKoha.pl' that finally starts (or stops) the daemon.
* It is strongly recommended to encrypt the communication between the regional ILL SLNPServer and ILLZFLServerKoha (e.g. by using stunnel)

## Configuration

The plugin configuration is an HTML text area in which a _YAML_ structure is pasted. The available options
are maintained on this document.

```yaml
---
portal_url: https://your.portal.url
```

*FIXME: this should all be moved to the YAML configuration page*
You have to adapt the default values of the additional ILL preferences loaded into table systempreferences by $PERL5LIB/Koha/Illbackends/SLNP/install/install.pl to your requirements.
The additional ILL preferences are listed with a short description in the load file $PERL5LIB/Koha/Illbackends/SLNP/install/insert_systempreferences.sql.
You may use the additional ILL letter layouts "as is" or you can adapt them to your needs. 
The additional ILL letter layouts are contained in the load file $PERL5LIB/Koha/Illbackends/SLNP/install/insert_letter.sql.

## Credits
This plugin is based on the original work from [LMSCLoud GmbH](https://github.com/LMSCloud/ILLSLNPKoha).
