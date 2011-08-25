$(document).ready(function() {
  $('a, .action, #content-index-bottom').live('mouseenter mouseleave', function(e) {

    var duration, txtColor;

    if (e.type == 'mouseenter') {
      duration = 100;
      txtColor = '#000';
    } else {
      duration = 240;
      txtColor = '#eee'; 
    }

    $(this).animate({'color':txtColor}, duration);
  });
});
