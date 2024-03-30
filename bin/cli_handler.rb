require 'ceedling/constants' # From Ceedling application

class CliHandler

  constructor :configinator, :projectinator, :cli_helper, :actions_wrapper, :logger

  def setup()
    # Aliases
    @helper = @cli_helper
    @actions = @actions_wrapper
  end

  # Complemented by `rake_tasks()` that can be called independently
  def app_help(env, app_cfg, command, &thor_help)
    # If help requested for a command, show it and skip listing build tasks
    if !command.nil?
      # Block handler
      thor_help.call( command ) if block_given?
      return
    end

    # Display Thor-generated help listing
    thor_help.call( command ) if block_given?

    # If it was help for a specific command, we're done
    return if !command.nil?

    # If project configuration is available, also display Rake tasks
    # Use project file defaults (since `help` allows no flags or options)
    rake_tasks( env:env, app_cfg:app_cfg ) if @projectinator.config_available?( env:env )
  end


  def new_project(ceedling_root, options, name, dest)
    @helper.set_verbosity( options[:verbosity] )

    # If destination is nil, reassign it to name
    # Otherwise, join the destination and name into a new path
    dest = dest.nil? ? ('./' + name) : File.join( dest, name )

    # Check for existing project (unless --force)
    if @helper.project_exists?( dest, :|, DEFAULT_PROJECT_FILENAME, 'src', 'test' )
      msg = "It appears a project already exists at #{dest}/. Use --force to destroy it and create a new project."
      raise msg
    end unless options[:force]

    # Blow away any existing directories and contents if --force
    @actions.remove_dir( dest ) if options[:force]

    # Create blank directory structure
    ['.', 'src', 'test', 'test/support'].each do |path|
      @actions._empty_directory( File.join( dest, path) )
    end

    # Vendor the tools and install command line helper scripts
    @helper.vendor_tools( ceedling_root, dest ) if options[:local]

    # Copy in documentation
    @helper.copy_docs( ceedling_root, dest ) if options[:docs]

    # Copy / set up project file
    @helper.create_project_file( ceedling_root, dest, options[:local] ) if options[:configs]

    @logger.log( "\n🌱 New project '#{name}' created at #{dest}/\n" )
  end


  def upgrade_project(ceedling_root, options, path)
    # Check for existing project
    if !@helper.project_exists?( path, :&, options[:project], 'vendor/ceedling/lib/ceedling.rb' )
      msg = "Could not find an existing project at #{path}/."
      raise msg
    end

    project_filepath = File.join( path, options[:project] )
    _, config = @projectinator.load( filepath:project_filepath, silent:true )

    if (@helper.which_ceedling?( config ) == 'gem')
      msg = "Project configuration specifies the Ceedling gem, not vendored Ceedling"
      raise msg
    end

    # Recreate vendored tools
    vendor_path = File.join( path, 'vendor', 'ceedling' )
    @actions.remove_dir( vendor_path )
    @helper.vendor_tools( ceedling_root, path )

    # Recreate documentation if we find docs/ subdirectory
    docs_path = File.join( path, 'docs' )
    founds_docs = @helper.project_exists?( path, :&, File.join( 'docs', 'CeedlingPacket.md' ) )
    if founds_docs
      @actions.remove_dir( docs_path )
      @helper.copy_docs( ceedling_root, path )
    end

    @logger.log( "\n🌱 Upgraded project at #{path}/\n" )
  end


  def app_exec(env, app_cfg, options, tasks)
    project_filepath, config = @configinator.loadinate( filepath:options[:project], mixins:options[:mixin], env:env )

    default_tasks = @configinator.default_tasks( config: config, default_tasks: app_cfg[:default_tasks] )

    @helper.process_testcase_filters(
      config: config,
      include: options[:test_case],
      exclude: options[:exclude_test_case],
      tasks: tasks,
      default_tasks: default_tasks
    )

    log_filepath = @helper.process_logging( options[:log], options[:logfile] )

    # Save references
    app_cfg[:project_config] = config
    app_cfg[:log_filepath] = log_filepath
    app_cfg[:include_test_case] = options[:test_case]
    app_cfg[:exclude_test_case] = options[:exclude_test_case]

    # Set graceful_exit from command line & configuration options
    app_cfg[:tests_graceful_fail] =
     @helper.process_graceful_fail(
        config: config,
        tasks: tasks,
        cmdline_graceful_fail: options[:graceful_fail]
      )

    # Enable setup / operations duration logging in Rake context
    app_cfg[:stopwatch] = @helper.process_stopwatch( tasks: tasks, default_tasks: default_tasks )

    @helper.set_verbosity( options[:verbosity] )

    @helper.load_ceedling( 
      project_filepath: project_filepath,
      config: config,
      which: app_cfg[:which_ceedling],
      default_tasks: default_tasks
    )

    @helper.run_rake_tasks( tasks )
  end

  def rake_exec(env:, app_cfg:, tasks:)
    project_filepath, config = @configinator.loadinate( env:env ) # Use defaults for project file & mixins

    default_tasks = @configinator.default_tasks( config: config, default_tasks: app_cfg[:default_tasks] )

    # Save references
    app_cfg[:project_config] = config

    # Enable setup / operations duration logging in Rake context
    app_cfg[:stopwatch] = @helper.process_stopwatch( tasks: tasks, default_tasks: default_tasks )

    @helper.set_verbosity() # Default verbosity

    @helper.load_ceedling( 
      project_filepath: project_filepath,
      config: config,
      which: app_cfg[:which_ceedling],
      default_tasks: default_tasks
    )

    @helper.run_rake_tasks( tasks )
  end

  def dumpconfig(env, app_cfg, options, filepath, sections)
    project_filepath, config = @configinator.loadinate( filepath:options[:project], mixins:options[:mixin], env:env )

    default_tasks = @configinator.default_tasks( config: config, default_tasks: app_cfg[:default_tasks] )

    # Save references
    app_cfg[:project_config] = config

    @helper.set_verbosity( options[:verbosity] )

    config = @helper.load_ceedling( 
      project_filepath: project_filepath,
      config: config,
      which: app_cfg[:which_ceedling],
      default_tasks: default_tasks
    )

    @helper.dump_yaml( config, filepath, sections )
  end

  def rake_tasks(env:, app_cfg:, project:nil, mixins:[], verbosity:nil)
    project_filepath, config = @configinator.loadinate( filepath:project, mixins:mixins, env:env )

    # Save reference to loaded configuration
    app_cfg[:project_config] = config

    @helper.set_verbosity( verbosity ) # Default to normal

    @helper.load_ceedling(
      project_filepath: project_filepath,
      config: config,
      which: app_cfg[:which_ceedling],
      default_tasks: app_cfg[:default_tasks]
    )

    @logger.log( 'Build operations:' )
    @helper.print_rake_tasks()
  end


  def create_example(ceedling_root, examples_path, options, name, dest)
    examples = @helper.lookup_example_projects( examples_path )

    if !examples.include?( name )
      raise( "No example project '#{name}' could be found" )
    end

    @helper.set_verbosity( options[:verbosity] )

    # If destination is nil, reassign it to name
    # Otherwise, join the destination and name into a new path
    dest = dest.nil? ? ('./' + name) : File.join( dest, name )

    dest_src      = File.join( dest, 'src' )
    dest_test     = File.join( dest, 'test' )
    dest_project  = File.join( dest, DEFAULT_PROJECT_FILENAME )

    @actions._directory( "examples/#{name}/src", dest_src )
    @actions._directory( "examples/#{name}/test", dest_test )
    @actions._copy_file( "examples/#{name}/#{DEFAULT_PROJECT_FILENAME}", dest_project )

    # Vendor the tools and install command line helper scripts
    @helper.vendor_tools( ceedling_root, dest ) if options[:local]

    # Copy in documentation
    @helper.copy_docs( ceedling_root, dest ) if options[:docs]

    @logger.log( "\n🌱 Example project '#{name}' created at #{dest}/\n" )
  end


  def list_examples(examples_path)
    examples = @helper.lookup_example_projects( examples_path )

    raise( "No examples projects found") if examples.empty?

    @logger.log( "\nAvailable exmple projects:" )

    examples.each {|example| @logger.log( " - #{example}" ) }

    @logger.log( "\n" )
  end


  def version()
    require 'ceedling/version'
    version = <<~VERSION
     🌱 Ceedling => #{Ceedling::Version::CEEDLING}
           CMock => #{Ceedling::Version::CMOCK}
           Unity => #{Ceedling::Version::UNITY}
      CException => #{Ceedling::Version::CEXCEPTION}
    VERSION
    @logger.log( version )
  end

end
