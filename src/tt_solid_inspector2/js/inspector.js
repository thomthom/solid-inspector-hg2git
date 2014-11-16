// Copyright 2014 Thomas Thomassen


$(document).ready(function() {

  $("#fix-all").on("click", function() {
    callback("fix_all");
  });

  $(document).on("click", ".error-group .expand_info", function() {
    var $this = $(this);
    $this.siblings(".description").toggle();
  });

  $(document).on("click", ".error-group > .fix", function() {
    var $this = $(this);
    var $error_group = $this.parent();
    var type = $error_group.data("type");
    var data = { "type" : type }
    callback("fix_group", data);
  });
});


function list_errors(errors) {
  $("#content").text("");
  for (error_type in errors) {
    var error_group = errors[error_type];
    add_error_type(error_group);
  }
}


function add_error_type(error_group) {
  html = '\
  <div class="error-group">\
    <div class="title">' + error_group.name + '</div>\
    <a class="expand_info">?</a>\
    <div class="count">' + error_group.errors.length + '</div>\
    <div class="description">' + error_group.description + '</div>\
    <button class="fix">Fix</button>\
  </div>';
  var $group = $(html);
  $group.data("type", error_group.type)
  $("#content").append($group);
}