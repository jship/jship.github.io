$(document).ready(function() {
  // fix menu when passed
  //$('.masthead').visibility({
  //  once: false,
  //  onBottomPassed: function() {
  //    $('.fixed.menu').transition('fade in');
  //  },
  //  onBottomPassedReverse: function() {
  //    $('.fixed.menu').transition('fade out');
  //  }
  //});

  // create sidebar and attach to menu open
  $('.ui.sidebar').sidebar('attach events', '.toc.item');

  var isTopLevelPage = false;
  $('.ui.menu a.item').each(function() {
    // update active menu item
    $(this).removeClass('active');
    if (document.title.indexOf($(this).text()) >= 0) {
      isTopLevelPage = true;
      $(this).addClass('active');
    }

    // avoid email spam
    if ($(this).text().indexOf('Email') >= 0) {
      var mkEmailLink = function() {
        return ["ja", "s", "onp", "ship", "man@gma", "il.com"].join('');
      };
      $(this).attr('href', 'mailto:' + mkEmailLink());
    }
  });

  // if not a top level page, for now, just assume on a specific blog post
  if (!isTopLevelPage) {
    $('.ui.menu a.item').each(function() {
      if ($(this).text().indexOf('Blog') >= 0) {
        $(this).addClass('active');
      }
    });
  }

  // right rail for RSS/Atom buttons on Blog (archive) page or specific post
  //$('.ui.sticky').sticky({
  //  context: '#blog_content',
  //  onStick: function() {
  //    $('.ui.sticky').animate({'margin-top': '1em'}, 200);
  //  }
  //});
});
