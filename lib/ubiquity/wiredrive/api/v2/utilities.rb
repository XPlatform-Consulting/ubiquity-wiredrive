require 'ubiquity/wiredrive/api/v2/client'

class Ubiquity::Wiredrive::API::V2::Utilities < Ubiquity::Wiredrive::API::V2::Client

  def asset_create_extended(args = { }, options = { })
    _args = args ? args.dup : { }
    project_name = _args.delete(:project_name) { }
    file_path = _args.delete(:file_path) { }

    if file_path
      file_name = File.basename(file_path)
      _args[:name] ||= file_name
    end

    if project_name
      _args[:project_id] ||= begin
        project = project_get_by_name(:name => project_name)
        raise ArgumentError, "Project Not Found by Name. '#{project_name}'" unless project
        project['id']
      end
    end

    asset = asset_create(_args, options)
    return unless asset

    if file_path
      asset_id = asset['id']
      location = asset_primary_file_init(:asset_id => asset_id)
      return unless location
      file_upload(:file_path => file_path, :destination_uri => location)
    end

    asset
  end

  def folder_create(args = { }, options = { })
    args_out = args.merge(:is_folder => true, :workflow => 'project')
    asset_create(args_out, options)
  end

  def folders_get(args = { }, options = { })
    args_out = args.merge(:is_folder => true)
    assets_get(args_out, options)
  end

  def project_get_by_name(args = { }, options = { })
    project_name = case args
                     when String; args
                     when Hash; args[:name]
                   end
    projects = projects_get( { :name => project_name }, options)
    projects.first
  end

  def path_check(path, path_contains_asset = false, options = { })
    return false unless path

    # Remove any and all instances of '/' from the beginning of the path
    path = path[1..-1] while path.start_with? '/'

    path_ary = path.split('/')

    existing_path_result = path_resolve(path, path_contains_asset, options)
    existing_path_ary = existing_path_result[:id_path_ary]
    check_path_length = path_ary.length

    # Get a count of the number of elements which were found to exist
    existing_path_length = existing_path_ary.length

    # Drop the first n elements of the array which corresponds to the number of elements found to be existing
    missing_path = path_ary.drop(existing_path_length)
    # In the following logic tree the goal is indicate what was searched for and what was found. If we didn't search
    # for the component (folder/asset) then we don't want to set the missing indicator var
    # (folder_missing/asset_missing) for component as a boolean but instead leave it nil.
    missing_path_length = missing_path.length
    if missing_path_length > 0
      # something is missing

      if missing_path_length == check_path_length
        # everything is missing in our path

        project_missing = true
        if path_contains_asset
          # we are missing everything and we were looking for an asset so it must be missing
          asset_missing = true

          if check_path_length > 2
            #if we were looking for more than two things (project, folder, and asset) and we are missing everything then folders are missing also
            searched_folders = true
            folder_missing = true
          else

            #if we are only looking for 2 things then that is only project and asset, folders weren't in the path so we aren't missing them
            searched_folders = false
            folder_missing = false
          end
        else
          if check_path_length > 1
            # If we are looking for more than one thing then it was project and folder and both are missing
            searched_folders = true
            folder_missing = true
          else
            searched_folders = false
            folder_missing = false
          end
        end
      else
        #we have found at least one thing and it starts with project
        project_missing = false
        if path_contains_asset
          #missing at least 1 and the asset is at the end so we know it's missing
          asset_missing = true
          if missing_path_length == 1
            #if we are only missing one thing and it's the asset then it's not a folder!
            folder_missing = false
            searched_folders = check_path_length > 2
          else
            # missing_path_length is more than 1
            if check_path_length > 2
              #we are looking for project, folder, and asset and missing at least 3 things so they are all missing
              searched_folders = true
              folder_missing = true
            else
              #we are only looking for project and asset so no folders are missing
              searched_folders = false
              folder_missing = false
            end
          end
        else
          #if we are missing something and the project was found and there was no asset then it must be a folder
          searched_folders = true
          folder_missing = true
        end
      end
    else
      searched_folders = !existing_path_result[:folders].empty?
      project_missing = folder_missing = asset_missing = false
    end

    {
      :check_path_ary => path_ary,
      :existing => existing_path_result,
      :missing_path => missing_path,
      :searched_folders => searched_folders,
      :project_missing => project_missing,
      :folder_missing => folder_missing,
      :asset_missing => asset_missing,
    }
  end

  def path_create(args = { }, options = { })
    args = { :path => args } if args.is_a?(String)
    logger.debug { "PATH CREATE: #{args.inspect}" }

    path = args[:path]
    raise ArgumentError, ':path is a required argument.' unless path

    contains_asset = args.fetch(:contains_asset, false)
    asset_file_path = args[:asset_file_path]
    overwrite_asset = args.fetch(:overwrite_asset, false)
    additional_asset_create_params = args[:additional_asset_create_params] || { }

    path_check_result = path_check(path, contains_asset)
    logger.debug { "CHECK PATH RESULT #{path_check_result.inspect}" }
    return false unless path_check_result

    project_missing = path_check_result[:project_missing]
    folder_missing = path_check_result[:folder_missing]
    asset_missing   = path_check_result[:asset_missing]

    existing = path_check_result[:existing]

    asset = existing[:asset]

    searched_folders = path_check_result[:searched_folders]

    missing_path = path_check_result[:missing_path]

    project_name = path_check_result[:check_path_ary][0]

    if project_missing
      logger.debug { "Missing Project - Creating Project '#{project_name}'" }
      project = project_create(:name => project_name)
      raise "Error Creating Project. Response: #{project}" unless project.is_a?(Hash)

      path_check_result[:project] = project
      project_id = project['id']
      missing_path.shift
      logger.debug { "Created Project '#{project_name}' - #{project_id}" }
    else
      project_id = existing[:id_path_ary].first
    end

    if searched_folders
      if folder_missing
        # logger.debug "FMP: #{missing_path}"

        parent_folder_id = (existing[:id_path_ary].length <= 1) ? 0 : existing[:id_path_ary].last

        asset_name = missing_path.pop if contains_asset

        previous_missing = project_missing
        missing_path.each do |folder_name|
          # sleep path_creation_delay if path_creation_delay and previous_missing
          begin
            logger.debug { "Creating folder '#{folder_name}' parent id: #{parent_folder_id} project id: #{project_id}" }
            new_folder = folder_create(:name => folder_name, :project_id => project_id, :parent_id => parent_folder_id)
            raise "Error Creating Folder. Response: #{new_folder}" unless new_folder.is_a?(Hash)

            logger.debug { "New Folder Created: #{new_folder.inspect}" }
            parent_folder_id = new_folder['id']
          rescue => e
            raise "Failed to create folder '#{folder_name}' parent id: '#{parent_folder_id}' project id: '#{project_id}'. Exception: #{e.message}"
          end
          previous_missing = true
        end

      else
        if contains_asset and not asset_missing
          parent_folder_id = existing[:id_path_ary].fetch(-2)
        else
          parent_folder_id = existing[:id_path_ary].last
        end
      end
    else
      parent_folder_id = nil
    end

    if contains_asset

      asset_name ||= File.basename(asset_file_path)
      additional_asset_create_params = { } unless additional_asset_create_params.is_a?(Hash)
      additional_asset_create_params[:parent_id] = parent_folder_id if parent_folder_id
      additional_asset_create_params[:project_id] = project_id
      additional_asset_create_params[:file_path] = asset_file_path
      additional_asset_create_params[:name] = asset_name
      additional_asset_create_params[:workflow] = 'project'

      logger.debug { "Path Create Asset Handling. Asset Missing: #{asset_missing} Create Args: #{additional_asset_create_params.inspect}" }

      if overwrite_asset and !asset_missing
        asset_id = existing[:id_path_ary].last
        begin
          raise "Error Message: #{error_message}" unless asset_delete(:id => asset_id)
        rescue => e
          raise e, "Error Deleting Existing Asset. Asset ID: #{asset_id} Exception: #{e.message}"
        end
        asset_missing = true
      end

      if asset_missing
        asset = asset_create_extended(additional_asset_create_params)
        raise "Error Creating Asset: #{asset.inspect} Args: #{additional_asset_create_params.inspect}" unless success?
      else
        # additional_asset_create_params = additional_asset_create_params.delete_if { |k,v| asset[k] == v }
        # asset_edit_extended(asset['id'], additional_asset_create_params) unless additional_asset_create_params.empty?
        # metadata_create_if_not_exists(asset['id'], metadata) if metadata and !metadata.empty?
      end

      path_check_result[:asset] = asset
    end
    result = path_check_result.merge({ :project_id => project_id, :parent_folder_id => parent_folder_id })
    logger.debug { "Create Missing Path Result: #{result.inspect}" }
    return result

  end


  def path_resolve(path, path_contains_asset = false, options = { })

    id_path_ary = [ ]
    name_path_ary = [ ]

    return_first_matching_asset = options.fetch(:return_first_matching_asset, true)

    if path.is_a?(String)
      # Remove any leading slashes
      path = path[1..-1] while path.start_with?('/')

      path_ary = path.split('/')
    elsif path.is_a?(Array)
      path_ary = path.dup
    else
      raise ArgumentError, "path is required to be a String or an Array. Path Class Name: #{path.class.name}"
    end

    asset_name = path_ary.pop if path_contains_asset

    # The first element must be the name of the project
    project_name = path_ary.shift
    raise ArgumentError, 'path must contain a project name.' unless project_name
    logger.debug { "Search for Project Name: #{project_name}" }
    projects = projects_get(:name => project_name)
    project = projects.first
    return {
      :name_path => '/',
      :name_path_ary => [ ],

      :id_path => '/',
      :id_path_ary => [ ],

      :project => nil,
      :asset => nil,
      :folders => [ ]
    } if !project or project.empty?

    project_id = project['id']
    id_path_ary << project_id
    name_path_ary << project_name

    parsed_folders = path_resolve_folder(project_id, path_ary)

    if parsed_folders.nil?
      asset_folder_id = 0
      folders         = []
    else
      id_path_ary.concat(parsed_folders[:id_path_ary])
      name_path_ary.concat(parsed_folders[:name_path_ary])
      asset_folder_id = parsed_folders[:id_path_ary].last if path_contains_asset
      folders         = parsed_folders.fetch(:folder_ary, [])
    end

    # ASSET PROCESSING - BEGIN
    asset = nil
    if path_contains_asset and (asset_folder_id or path_ary.length == 2)
      assets = assets_get(:name => asset_name, :is_folder => false, :project_id => project_id, :parent_id => asset_folder_id)
      if assets and !assets.empty?
        assets = [ assets.first ] if return_first_matching_asset
        # Just add the whole array to the array
        id_path_ary.concat assets.map { |_asset| _asset['id'] }
        name_path_ary.concat assets.map { |_asset| _asset['name'] }
      end
    end

    # ASSET PROCESSING - END

    {
      :name_path => "/#{name_path_ary.join('/')}",
      :name_path_ary => name_path_ary,

      :id_path => "/#{id_path_ary.join('/')}",
      :id_path_ary => id_path_ary,

      :project => project,
      :asset => asset,
      :folders => folders
    }
  end

  def path_resolve_folder(project_id, path, parent_id = nil)
    if path.is_a?(Array)
      path_ary = path.dup
    elsif path.is_a? String
      path = path[1..-1] while path.start_with?('/')
      path_ary = path.split('/')
    end

    return nil if !path_ary or path_ary.empty?

    id_path_ary = [ ]
    name_path_ary = [ ]

    folder_name = path_ary.shift
    name_path_ary << folder_name

    args_out = {
      :project_id => project_id,
      :name => folder_name
    }
    args_out[:parent_id] = parent_id if parent_id

    folders = folders_get(args_out)
    folder = folders.first
    return nil unless folder

    folder_ary = [ folder ]

    folder_id = folder['id']

    id_path_ary << folder_id.to_s

    resolved_folder_path = path_resolve_folder(project_id, path_ary, folder_id)

    unless resolved_folder_path.nil?
      id_path_ary.concat(resolved_folder_path[:id_path_ary] || [ ])
      name_path_ary.concat(resolved_folder_path[:name_path_ary] || [ ])
      folder_ary.concat(resolved_folder_path[:folder_ary] || [ ])
    end

    {
      :id_path_ary => id_path_ary,
      :name_path_ary => name_path_ary,
      :folder_ary => folder_ary
    }
  end


end

