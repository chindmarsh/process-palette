MainView = require './views/main-view'
ConfigsView = require './views/configs-view'
MainEditView = require './views/edit/main-edit-view'
ProjectController = require './controllers/project-controller'
Path = require 'path'
_ = require 'underscore-plus'
{File, CompositeDisposable} = require 'atom'

module.exports = ProcessPalette =

  config:
    shell:
      description: "The shell to run commands with. Leave empty for system default to be used."
      type: "string"
      default: ""

  activate: (@state) ->
    @dirty = false;
    @subscriptions = new CompositeDisposable
    @projectControllers = []
    @mainView = new MainView(@)
    @bottomPanel = atom.workspace.addBottomPanel(item: @mainView.getElement(), visible: false);

    @subscriptions.add atom.commands.add 'atom-workspace', 'process-palette:show': => @showPanel()
    @subscriptions.add atom.commands.add 'atom-workspace', 'process-palette:hide': => @hidePanel()
    @subscriptions.add atom.commands.add 'atom-workspace', 'process-palette:toggle': => @togglePanel()
    @subscriptions.add atom.commands.add 'atom-workspace', 'process-palette:rerun-last': => @runLast()
    @subscriptions.add atom.commands.add 'atom-workspace', 'process-palette:edit-configuration': => @editConfiguration()
    @subscriptions.add atom.commands.add 'atom-workspace', 'process-palette:reload-configuration': => @reloadConfiguration()
    @subscriptions.add atom.commands.add 'atom-workspace',
      'core:cancel': => @hidePanel()
      'core:close': => @hidePanel()

    # TODO : Enable this again later to support 'on-save' behavior.
    # @subscriptions.add atom.workspace.observeTextEditors (editor) =>
    #   @subscriptions.add editor.onDidSave (event) =>
    #     @fileSaved(event.path);

    @load();

    if _.isNumber(@state.height)
      @mainView.setViewHeight(@state.height);

    if @state.visible
      @bottomPanel.show();

  deactivate: ->
    @subscriptions.dispose();
    @disposeProjectControllers();
    @mainView.destroy();

  disposeProjectControllers: ->
    for projectController in @projectControllers
      projectController.dispose();

  serialize: ->
    if @mainView != null
      state = {};
      state.visible = @bottomPanel.isVisible();
      state.height = @mainView.viewHeight;
      return state;

    return @state;

  fileSaved: (path) ->
    for projectController in @projectControllers
      projectController.fileSaved(path);

  load: ->
    # Remove all key bindings.
    atom.keymaps.removeBindingsFromSource('process-palette');

    configFile = new File(atom.config.getUserConfigPath());
    @addProjectPath(configFile.getParent().getRealPathSync());

    for projectPath in atom.project.getPaths()
      @addProjectPath(projectPath);

    atom.project.onDidChangePaths (paths) => @projectsChanged(paths)

  projectsChanged: (paths) ->
    # Add controllers for new project paths.
    for path in paths
      if @getProjectControllerWithPath(path) == null
        @addProjectPath(path);

    # Remove controllers of old project paths.
    toRemove = [];
    for projectCtrl in @projectControllers
      if !projectCtrl.isGlobal() and paths.indexOf(projectCtrl.getProjectPath()) < 0
        toRemove.push(projectCtrl);

    if toRemove.length == 0
      return;

    @showListView();

    for projectCtrl in toRemove
      @removeProjectController(projectCtrl);

  getProjectControllerWithPath: (projectPath) ->
    for projectController in @projectControllers
      if projectController.getProjectPath() == projectPath
        return projectController;

    return null;

  reloadConfiguration: (saveEditors = true)->
    if saveEditors
      @saveEditors();

    if @mainView.isOutputViewVisible()
      @mainView.showListView();

    for projectController in @projectControllers
      projectController.dispose();

    @projectControllers = [];
    @load();

    atom.notifications.addInfo("Process Palette configurations reloaded");

  togglePanel: ->
    if @bottomPanel.visible
      @bottomPanel.hide();
    else
      @bottomPanel.show();

  showPanel: ->
    if !@bottomPanel.visible
      @bottomPanel.show();

  hidePanel: ->
    if @bottomPanel.visible
      @bottomPanel.hide();

  runLast: ->
    configController = @getLastRunConfigController();
    configController?.runProcess();

  showListView: ->
    @showPanel();
    @mainView.showListView();

  showProcessOutput: (processController) ->
    @showPanel();
    @mainView.showProcessOutput(processController);

  isProcessOutputShown: (processController) ->
    return @mainView.isProcessOutputShown(processController);

  processControllerRemoved: (processController) ->
    @mainView.processControllerRemoved(processController);

  addProjectPath: (projectPath) ->
    projectController = new ProjectController(@, projectPath);
    @projectControllers.push(projectController);

  removeProjectController: (projectController) ->
    index = @projectControllers.indexOf(projectController);

    if index < 0
      return;

    @projectControllers.splice(index, 1);
    projectController.dispose();

  editConfiguration: (showGlobal = true) ->
    view = new ConfigsView(@, showGlobal);
    # for projectController in @projectControllers
    #   projectController.editConfiguration();

  guiEditConfiguration: (global, projectName, folderPath) ->
    if global
      title = 'Global Commands';
    else
      title = projectName;

    # If there is a process-palette.json file then open it. If not then
    # create a new file and load the example into it.
    file = new File(Path.join(folderPath, 'process-palette.json'));

    if !file.existsSync()
      packagePath = atom.packages.getActivePackage('process-palette').path;
      exampleFile = new File(Path.join(packagePath, 'examples', 'process-palette.json'));

      exampleFile.read(false).then (content) =>
        file.create().then =>
          file.writeSync(content);
          @guiOpenFile(title, file);
    else
      @guiOpenFile(title, file);

  guiEditCommand: (configController) ->
    projectController = configController.getProjectController();
    file = projectController.getConfigurationFile();
    action = configController.getConfig().action;

    if projectController.isGlobal()
      title = 'Global Commands';
    else
      title = projectController.getProjectName();

    @guiOpenFile(title, file, action);

  guiOpenFile: (title, file, selectedAction = null) ->
    # If the file is already open then activate its pane.
    filePath = file.getRealPathSync();
    paneItem = @getPaneItem(filePath);
    pane = atom.workspace.getActivePane();

    if paneItem != null
      pane.activateItem(paneItem);
      return;

    main = @;

    file.read(false).then (content) =>
      config = JSON.parse(content);
      if !_.isObject(config.patterns)
        config.patterns = {};
      if !_.isArray(config.commands)
        config.commands = [];
      view = new MainEditView(main, title, filePath, config, selectedAction);
      paneItem = pane.addItem(view, 0);
      pane.activateItem(paneItem);

  # Called when the save button was pressed. This saves changes that were made
  # to the command directly in the panel.
  savePanel: ->
    for projectController in @projectControllers
      projectController.saveFile();

    @setDirty(false);

  saveEditors: ->
    paneItems = atom.workspace.getPaneItems();

    for paneItem in paneItems
      if paneItem instanceof MainEditView
        paneItem.saveChanges();

    @setDirty(false);

  getPaneItem: (filePath) ->
    paneItems = atom.workspace.getPaneItems();

    for paneItem in paneItems
      if paneItem instanceof MainEditView
        if paneItem.filePath == filePath
          return paneItem;

    return null;

  getConfigController: (namespace, action) ->
    for projectController in @projectControllers
      configController = projectController.getConfigController(namespace, action);

      if processController
        return processController;

    return null;

  getLastRunConfigController: ->
    result = null;
    configControllers = @getAllConfigControllers();

    for configController in configControllers
      lastTime = configController.getLastTime();

      if lastTime?
        if !result? or result.getLastTime() < lastTime
          result = configController;

    return result;

  getAllConfigControllers: ->
    result = [];

    for projectController in @projectControllers
      result = result.concat(projectController.getConfigControllers());

    return result;

  setDirty: (dirty) ->
    if @dirty != dirty
      @dirty = dirty;
      @mainView.setSaveButtonVisible(@dirty);
