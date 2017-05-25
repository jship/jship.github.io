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

  // update active menu item
  $('.ui.menu a.item').each(function() {
    $(this).removeClass('active');
    if (document.title.indexOf($(this).text()) >= 0) {
      $(this).addClass('active');
    }
  });
});
