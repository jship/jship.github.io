# jship.github.io
Personal blog

## Temporary semantic ui notes

* Install NodeJS: https://nodejs.org/en/
* Globally install gulp: `npm install -g gulp`
* Install Semantic UI:

```
npm install semantic-ui --save
cd semantic/
gulp build
```

* Running the gulp build tools will compile CSS and Javascript for use in your project. Just link to these files in your HTML along with the latest jQuery.

```
<link rel="stylesheet" type="text/css" href="semantic/dist/semantic.min.css">
<script
  src="https://code.jquery.com/jquery-3.1.1.min.js"
  integrity="sha256-hVVnYaiADRTO2PzUGmuLJr8BLUSjGIZsDYGmIJLv2b8="
  crossorigin="anonymous"></script>
<script src="semantic/dist/semantic.min.js"></script>
```

* To update Semantic UI: `npm update`
