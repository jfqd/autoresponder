= Autoresponder script

== Installation

Copy all files to /var/lib/vmail/, change your values in the env-file, rename it to .env and chmod 0600 the new dot file.

```
cd /folder/of/this/readme
mkdir -p /var/lib/vmail
cp * /var/lib/vmail/
mv /var/lib/vmail/env /var/lib/vmail/.env
chmod 0600 /var/lib/vmail/.env
```

To install all ruby dependencies install bundler and run it:

```
cd /var/lib/vmail
gem install bundler
bundle
```

You may wanna create a cron entry to process /var/lib/vmail/autoresponder regulary:

```
0,5,10,15,20,25,30,35,40,45,50,55 * * * * /usr/bin/test -x /var/lib/vmail/autoresponder && /var/lib/vmail/autoresponder 1>>/var/log/autoresponder.log
```

(c) 2018 S. Husch | qutic.com