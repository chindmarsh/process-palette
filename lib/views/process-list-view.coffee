ProcessView = require './process-view'
ProcessOutputView = require './process-output-view'
{CompositeDisposable} = require 'atom'
{$$, View} = require 'atom-space-pen-views'

module.exports =
class ProcessListView extends View

  constructor: (@main) ->
    super(@main);
    @processViews = [];

  @content: ->
    @div =>
      @button {class:'close-button btn btn-xs icon-chevron-down inline-block-tight', click:'hide'}
      @div {class:"scrollable", outlet:"processList"}
      @div {outlet:"processOutput"}

  hide: ->
    @main.hide();

  addProcess: (processController) =>
    processView = new ProcessView(@, processController);
    @processViews.push(processView);

    @processList.append $$ ->
      @div =>
        @subview processController.config.id, processView

  removeProcess: (processController) =>
    processView = @getProcessView(processController);

    if processView
      index = @processViews.indexOf(processView);
      @processViews.splice(index, 1);
      processView.destroy();

  getProcessView: (processController) =>
    for processView in @processViews
      if processView.processController == processController
        return processView;

    return null;

  showProcessList: =>
    @processList.removeClass("hidden");

    if @processOutputView
      @processOutputView.destroy();
      @processOutputView = null;

    @processOutput.text("");

  showProcessOutput: (processController) =>
    # If output is already shown then first remove it.
    if @processOutputView
      @processOutputView.destroy();

    @processList.addClass("hidden");
    @processOutputView = new ProcessOutputView(@, processController);

    f = () =>
      return @processOutputView;

    @processOutput.append $$ ->
      @div =>
        @subview "processController.config.id", f()

    # Ensure that the panel is visible.
    @main.show();

  # Returns an object that can be retrieved when package is activated
  serialize: ->

  # Tear down any state and detach
  destroy: ->
    @element.remove();

  getElement: ->
    @element