# cfwebapp

## Description

Module with web application "recipes" on top of [cfweb](https://codingfuture.net/docs/cfweb) module.

## Apps supported

* Kibana
* Redmine

### Kibana

A fake RMS package is created from /usr/share/kibana setup coming from the official package. So, it should be
always up to date. No auto-configuration is performed.

*Note: Kibana listens to loopback by default in case of accident misconfiguration.*

* URL: [www.elastic.co](https://www.elastic.co/guide/en/kibana/current/introduction.html)
* General `cfweb::site` shortcuts
    * `$server_name = $title`
    * `$ifaces = ['local']`
    * `$auto_cert = {}`
    * `$shared_cert = []`
    * `$robots_noindex = true`
    * `$site_params = {}` - other `cfweb::site` params
* `futoin` app shortcuts:
    * `$memory_weight = 100`
    * `$memory_min = 404`
    * `$memory_max = undef`
* Kibana-specific:
    * `$app_dbaccess = { cluster => 'logsink' }` - define cfdb::access to cflogsink cluster
    * `$plugins = []` - list of plugins to install per instance
    * `$kibana_tune = {}` - custom overrides for `kibana.yml`


### Redmine

Full Redmine deployment. By default SVN tags are used.

IMAP IDLE-based polling supported. Good for low incoming email count.

* URL: [www.redmine.org](http://www.redmine.org/)
* General `cfweb::site` shortcuts
    * `$server_name = $title`
    * `$auto_cert = {}`
    * `$shared_cert = []`
    * `$robots_noindex = true`
    * `$site_params = {}` - other `cfweb::site` params
* `futoin` app shortcuts:
    * `$memory_weight = 100`
    * `$memory_min = 404`
    * `$memory_max = undef`
* Redmine-specific
    * `$app_dbaccess` - DB access definition
    * `$deploy_type = 'vcstag'`
    * `$deploy_tool = 'svn'`
    * `$deploy_url = 'http://svn.redmine.org/redmine'`
    * `$deploy_match = '3.4.*'`
    * `$ruby_ver = '2.3'`
    * `$rake_secret = undef` - auto-gen by default
    * '$smtp' - SMTP configuration
    * '$imap' - IMAP configuration
    * `$plugins` - hash of name => params to install. Default:
        * 'redmine_telegram_common' for 'redmine_2fa'
        * 'redmine_2fa'
        * 'redmine_issue_checklist'

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

Up to date installation instructions are available in Puppet Forge: https://forge.puppet.com/codingfuture/cfwebapp

Please use [librarian-puppet](https://rubygems.org/gems/librarian-puppet/) or
[cfpuppetserver module](https://codingfuture.net/docs/cfpuppetserver) to deal with dependencies.

There is a known r10k issue [RK-3](https://tickets.puppetlabs.com/browse/RK-3) which prevents
automatic dependencies of dependencies installation.
