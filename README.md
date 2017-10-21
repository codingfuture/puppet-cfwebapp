# cfwebapp

## Description

Module with web application "recipes" on top of [cfweb](https://github.com/codingfuture/puppet-cfweb) module.

**This module is still in development!**

## Apps supported

### Redmine

Full Redmine deployment. By default SVN tags are used.

IMAP IDLE-based polling supported. Good for low incoming email count.

* URL: [www.redmine.org](http://www.redmine.org/)
* See cfweb::site for main parameters
* `$app_dbaccess` - DB access definition
* `$deploy_type = 'vcstag'`
* `$deploy_tool = 'svn'`
* `$deploy_url = 'http://svn.redmine.org/redmine'`
* `$deploy_match = '3.4.*'`
* `$ruby_ver = '2.3'`
* '$smtp' - SMTP configuration
* '$imap' - IMAP configuration

Example:

```yaml
    cfweb::global::sites:
        redmine:
            type: 'cfwebapp::redmine'
            server_name: redmine.example.com
            app_dbaccess:
                cluster: mysrv
                role: redmine
            memory_max: 512
        smtp:
            host: smtp.gmail.com
            port: 587
            start_tls: true
            user: 'user@gmail.com'
            password: pass
            reply_to: 'noreply@gmail.com'
        imap:
            host: imap.gmail.com
            port: 993
            user: 'user@gmail.com'
            password: pass
            ssl: true
```


## Technical Support

* [Example configuration](https://github.com/codingfuture/puppet-test)
* Free & Commercial support: [support@codingfuture.net](mailto:support@codingfuture.net)

## Setup

Please use [librarian-puppet](https://rubygems.org/gems/librarian-puppet/) or
[cfpuppetserver module](https://forge.puppetlabs.com/codingfuture/cfpuppetserver) to deal with dependencies.

There is a known r10k issue [RK-3](https://tickets.puppetlabs.com/browse/RK-3) which prevents
automatic dependencies of dependencies installation.
