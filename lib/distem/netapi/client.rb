require 'distem'
require 'rest_client'
require 'json'
require 'cgi'
require 'uri'
require 'pp'

module Distem
  module NetAPI

    CLASSMAP = {
        Hash => lambda { |x| x.to_json },
        String => lambda { |x| x },
        TrueClass => lambda { |x| x },
        FalseClass => lambda { |x| x },
        Numeric => lambda { |x| x },
        NilClass => lambda { |x| x }
    }

    # Distem ruby client
    # @note For +desc+ parameters, the only elements in the structure (Hash) that will be taken in account are those listed as *writable* in {file:files/resources_desc.md Resources Description}.
    # @note Most of changes you can perform on virtual nodes resources are taking effect after stopping then starting back the resource. Changes that are applied on-the-fly are documented as this.
    class Client
      # The maximum number of simultaneous requests
      MAX_SIMULTANEOUS_REQ = 64
      # The HTTP OK status value
      # @private
      HTTP_STATUS_OK = 200
      # The default timeout
      TIMEOUT=900

      @@semreq = Lib::Semaphore.new(MAX_SIMULTANEOUS_REQ)

      # Create a new Client and connect it to a specified REST(distem) server
      #
      # @param [String] serveraddr The REST server address
      # @param [Numeric] port The port the REST server is listening on
      #
      def initialize(serveraddr="localhost",port=4567, semsize = nil)
        raise unless port.is_a?(Numeric)
        @serveraddr = serveraddr
        @serverurl = 'http://' + @serveraddr + ':' + port.to_s
        @resource = RestClient::Resource.new(@serverurl, :timeout => TIMEOUT, :open_timeout => (TIMEOUT/2))
        @@semreq = Lib::Semaphore.new(semsize) if semsize and @@semreq.size != semsize
        @resource
      end

      # Initialize a physical machine (launching daemon, creating cgroups, ...).
      # This step have to be performed to be able to create virtual nodes on a machine.
      #
      # @param [String] target The hostname/address of the physical node
      # @param [Hash] desc Hash structured as described in {file:files/resources_desc.md#Physical_Nodes Resource Description - PNodes}.
      # @param [Boolean] async Asynchronious mode, check the physical node status to know when the configuration is done (see {#pnode_info})
      # @return [Hash] The physical node description (see {file:files/resources_desc.md#Physical_Nodes Resource Description - PNodes}).
      def pnode_init(target = 'localhost', desc = {}, async=false)
        post_json("/pnodes", { :target => target, :desc => desc, :async => async })
      end

      # Asynchronious version of {#pnode_init}.
      #
      # @return [Hash] The physical node description (see {file:files/resources_desc.md#Physical_Nodes Resource Description - PNodes}).
      def pnode_init!(target = 'localhost', desc = {})
        return pnode_init(target,desc,true)
      end

      # Quit distem on a physical machine
      #
      # @param [String] target The hostname/address of the physical node
      # @return [Hash] The physical node description (see {file:files/resources_desc.md#Physical_Nodes Resource Description - PNodes}).
      def pnode_quit(target='localhost')
        delete_json("/pnodes/#{target}")
      end

      # Update the physical node
      #
      # @param [String] target The hostname/address of the physical node
      # @param [Hash] desc Hash structured as described in {file:files/resources_desc.md#Physical_Nodes Resource Description - PNodes}.
      # @return [Hash] The physical node description (see {file:files/resources_desc.md#Physical_Nodes Resource Description - PNodes}).
      def pnode_update(target='localhost', desc={})
        put_json("/pnodes/#{target}", { :desc => desc })
      end

      # Retrieve informations about a physical node
      #
      # @param [String] target The address/name of the physical node
      # @return [Hash] The physical node description (see {file:files/resources_desc.md#Physical_Nodes Resource Description - PNodes}).
      def pnode_info(target='localhost')
        get_json("/pnodes/#{target}")
      end

      # Quit distem on every physical machine
      #
      # @return [Array] Array of physical node descriptions (see {file:files/resources_desc.md#Physical_Nodes Resource Description - PNodes}).
      def pnodes_quit()
        delete_json("/pnodes")
      end

      # Retrieve informations about every physical nodes currently set on the platform
      #
      # @return [Array] Array of physical node descriptions (see {file:files/resources_desc.md#Physical_Nodes Resource Description - PNodes}).
      def pnodes_info()
        get_json("/pnodes")
      end

      # Retrieve information about the CPU of a physical node
      #
      # @param [String] target The address/name of the physical node
      # @return [Hash] The physical node description (see {file:files/resources_desc.md#CPU Resource Description - PCPU}).
      def pcpu_info(target='localhost')
        get_json("/pnodes/#{target}/cpu")
      end

      # Retrieve information about the memory of a physical node
      #
      # @param [String] target The address/name of the physical node
      # @return [Hash] The physical node description (see {file:files/resources_desc.md#Memory Resource Description - PMemory}).
      def pmemory_info(target='localhost')
        get_json("/pnodes/#{target}/memory")
      end

      # Create a new virtual node
      # @param [String] name The name of the virtual node which should be unique
      # @param [Hash] desc Hash structured as described in {file:files/resources_desc.md#Virtual_Nodes Resource Description - VNodes}.
      # @param [Hash] ssh_key SSH key pair to be copied on the virtual node (also adding the public key to .ssh/authorized_keys). Note that every SSH keys located on the physical node which hosts this virtual node are also copied in .ssh/ directory of the node (copied key have a specific filename prefix). The key are copied in .ssh/ directory of SSH user (see {Distem::Daemon::Admin#SSH_USER} and Distem::Node::Container::SSH_KEY_FILENAME)
      #
      #     _Format_: Hash.
      #
      #     _Structure_:
      #       {
      #         "public" : "KEYHASH",
      #         "private" : "KEYHASH"
      #       }
      #     Both of +public+ and +private+ parameters are optional
      # @param [Boolean] async Asynchronious mode, check virtual node status to know when node is configured (see {#vnode_info})
      # @return [Hash] The virtual node description (see {file:files/resources_desc.md#Virtual_Nodes Resource Description - VNodes})
      def vnode_create(name, desc = {}, ssh_key={}, async=false)
        post_json('/vnodes', { :name => name , :desc => desc, :ssh_key => ssh_key, :async => async })
      end

      # Remove the virtual node
      # @note "Cascade" removing: remove all the vroutes in which this virtual node apears as gateway
      #
      # @param [String] vnodename The name of the virtual node
      # @return [Hash] The virtual node description (see {file:files/resources_desc.md#Virtual_Nodes Resource Description - VNodes})
      def vnode_remove(vnodename)
        delete_json("/vnodes/#{URI.escape(vnodename)}")
      end

      # Update a virtual node description
      #
      # @param [String] vnodename The name of the virtual node
      # @param [Hash] desc Hash structured as described in {file:files/resources_desc.md#Virtual_Nodes Resource Description - VNodes}.
      # @param [Boolean] async Asynchronious mode, check virtual node status to know when node is configured (see {#vnode_info})
      # @return [Hash] The virtual node description (see {file:files/resources_desc.md#Virtual_Nodes Resource Description - VNodes})
      def vnode_update(vnodename, desc = {}, async=false)
        put_json("/vnodes/#{URI.escape(vnodename)}", { :desc => desc, :async => async })
      end

      # Retrieve informations about a virtual node
      #
      # @param [String] vnodename The name of the virtual node
      # @return [Hash] The virtual node description (see {file:files/resources_desc.md#Virtual_Nodes Resource Description - VNodes})
      def vnode_info(vnodename)
        get_json("/vnodes/#{URI.escape(vnodename)}")
      end

      # Start a virtual node.
      #
      # @note A physical node (that have enought physical resources (CPU,...)) will be automatically allocated if there is none set as +host+ at the moment
      # @note The filesystem archive will be copied on the hosting physical node.
      # @note A filesystem image *must* have been set (see {#vnode_create} or {#vfilesystem_create}/{#vfilesystem_update}).
      #
      # @param [String] vnodename The name of the virtual node
      # @param [Boolean] async Asynchronious mode, check virtual node status to know when node is configured (see {#vnode_info})
      # @return [Hash] The virtual node description (see {file:files/resources_desc.md#Virtual_Nodes Resource Description - VNodes})
      def vnode_start(vnodename, async=false)
        desc = { :status => Resource::Status::RUNNING }
        put_json("/vnodes/#{URI.escape(vnodename)}", { :desc => desc, :async => async })
      end

      # Same as {#vnode_start} but in asynchronious mode
      #
      # @return [Hash] The virtual node description (see {file:files/resources_desc.md#Virtual_Nodes Resource Description - VNodes})
      def vnode_start!(vnodename)
        return vnode_start(vnodename,true)
      end

      # Stopping a virtual node, deleting it's data from the hosting physical node.
      # @note The +host+ association for this virtual node will be cancelled, if you start the virtual node directcly after stopping it, the hosting physical node will be chosen randomly (to set it manually, see host field, {#vnode_update})
      #
      # @param [String] vnodename The name of the virtual node
      # @param [Boolean] async Asynchronious mode, check virtual node status to know when node is configured (see {#vnode_info})
      # @return [Hash] The virtual node description (see {file:files/resources_desc.md#Virtual_Nodes Resource Description - VNodes})
      def vnode_stop(vnodename, async=false)
        desc = { :status => Resource::Status::READY }
        put_json("/vnodes/#{URI.escape(vnodename)}", { :desc => desc, :async => async })
      end

      # Same as {#vnode_stop} but in asynchronious mode
      #
      # @return [Hash] The virtual node description (see {file:files/resources_desc.md#Virtual_Nodes Resource Description - VNodes})
      def vnode_stop!(vnodename)
        return vnode_stop(vnodename, true)
      end

      # Set the mode of a virtual node
      # @param [String] vnodename The name of the virtual node
      # @param [Boolean] gateway Gateway mode: add the ability to forward traffic
      # @return [Hash] The virtual node description (see {file:files/resources_desc.md#Virtual_Nodes Resource Description - VNodes})
      def vnode_mode(vnodename,gateway=true)
        desc = { :mode => gateway ? Resource::VNode::MODE_GATEWAY : Resource::VNode::MODE_NORMAL }
        put_json("/vnodes/#{URI.escape(vnodename)}", { :desc => desc })
      end

      # Remove all vnodes
      #
      # @return [Array] Array of virtual nodes description (see {file:files/resources_desc.md#Virtual_Nodes Resource Description - VNodes})
      def vnodes_remove()
        delete_json("/vnodes")
      end

      # Retrieve informations about every virtual nodes currently set on the platform
      #
      # @return [Array] Array of virtual nodes description (see {file:files/resources_desc.md#Virtual_Nodes Resource Description - VNodes})
      def vnodes_info()
        get_json("/vnodes")
      end

      # Execute and get the result of a command on a virtual node
      #
      # @param [String] vnodename The name of the virtual node
      # @param [String] command The command to be executed
      # @return [String] The result of the command (Array of string if multilines)
      def vnode_execute(vnodename, command)
        post_json("/vnodes/#{URI.escape(vnodename)}/commands", { :command => command })
      end

      # Create a virtual network interface on the virtual node
      #
      # @param [String] vnodename The name of the virtual node
      # @param [String] name The name of the virtual network interface to be created (have to be unique on that virtual node)
      # @param [Hash] desc Hash structured as described in {file:files/resources_desc.md#Network_interface Resource Description - VIface}.
      # @return [Hash] The virtual network interface description (see {file:files/resources_desc.md#Network_Interfaces Resource Description - VIfaces})
      def viface_create(vnodename, name, desc)
        post_json("/vnodes/#{URI.escape(vnodename)}/ifaces", { :name => name, :desc => desc })
      end

      # Remove a virtual network interface
      #
      # @param [String] vnodename The name of the virtual node
      # @param [String] vifacename The name of the network virtual interface
      # @return [Hash] The virtual network interface description (see {file:files/resources_desc.md#Network_Interfaces Resource Description - VIfaces})
      def viface_remove(vnodename,vifacename)
        delete_json("/vnodes/#{URI.escape(vnodename)}/ifaces/#{URI.escape(vifacename)}")
      end

      # Update a virtual network interface
      #
      # @note Disconnect (detach) the virtual network interface from any virtual network it's connected on if +desc+ is empty
      #
      # @param [String] vnodename The name of the virtual node
      # @param [String] vifacename The name of the virtual network interface
      # @param [Hash] desc Hash structured as described in {file:files/resources_desc.md#Network_interface Resource Description - VIface}.
      # @return [Hash] The virtual network interface description (see {file:files/resources_desc.md#Network_Interfaces Resource Description - VIfaces})
      def viface_update(vnodename, vifacename, desc = {})
        put_json("/vnodes/#{URI.escape(vnodename)}/ifaces/#{URI.escape(vifacename)}", { :desc => desc })
      end

      # Update the traffic description on the input of a specified virtual network interface
      # @note The vtraffic description is updated on-the-fly (even if the virtual node is running)
      # @note Reset the vtraffic description if +desc+ is empty
      #
      # @param [String] vnodename The name of the virtual node
      # @param [String] vifacename The name of the virtual network interface
      # @param [Hash] desc Hash structured as described in {file:files/resources_desc.md#Virtual_Traffic Resource Description - VTraffic}.
      # @return [Hash] The virtual traffic description (see {file:files/resources_desc.md#Traffic Resource Description - VTraffic})
      def vinput_update(vnodename, vifacename, desc = {})
        put_json("/vnodes/#{URI.escape(vnodename)}/ifaces/#{URI.escape(vifacename)}/input", { :desc => desc })
      end

      # Retrive the traffic description on the input of a specified virtual network interface
      #
      # @param [String] vnodename The name of the virtual node
      # @param [String] vifacename The name of the virtual network interface
      # @return [Hash] The virtual traffic description (see {file:files/resources_desc.md#Traffic Resource Description - VTraffic})
      def vinput_info(vnodename, vifacename)
        get_json("/vnodes/#{URI.escape(vnodename)}/ifaces/#{URI.escape(vifacename)}/input")
      end

      # Update the traffic description on the output of a specified virtual network interface
      # @note The vtraffic description is updated on-the-fly (even if the virtual node is running)
      # @note Reset the vtraffic description if +desc+ is empty
      #
      # @param [String] vnodename The name of the virtual node
      # @param [String] vifacename The name of the virtual network interface
      # @param [Hash] desc Hash structured as described in {file:files/resources_desc.md#Virtual_Traffic Resource Description - VTraffic}.
      # @return [Hash] The virtual traffic description (see {file:files/resources_desc.md#Traffic Resource Description - VTraffic})
      def voutput_update(vnodename, vifacename, desc = {})
        put_json("/vnodes/#{URI.escape(vnodename)}/ifaces/#{URI.escape(vifacename)}/output", { :desc => desc })
      end

      # Retrive the traffic description on the output of a specified virtual network interface
      #
      # @param [String] vnodename The name of the virtual node
      # @param [String] vifacename The name of the virtual network interface
      # @return [Hash] The virtual traffic description (see {file:files/resources_desc.md#Traffic Resource Description - VTraffic})
      def voutput_info(vnodename, vifacename)
        get_json("/vnodes/#{URI.escape(vnodename)}/ifaces/#{URI.escape(vifacename)}/output")
      end

      # Retrieve informations about a virtual network interface associated to a virtual node
      #
      # @param [String] vnodename The name of the virtual node
      # @param [String] vifacename The name of the virtual network interface
      # @return [Hash] The virtual network interface description (see {file:files/resources_desc.md#Network_Interfaces Resource Description - VIfaces})
      def viface_info(vnodename, vifacename)
        get_json("/vnodes/#{URI.escape(vnodename)}/ifaces/#{URI.escape(vifacename)}")
      end

      # Set up a virtual CPU on the virtual node
      #
      # @param [String] vnodename The name of the virtual node
      # @param [Integer] corenb The number of cores to allocate (need to have enough free ones on the physical node)
      # @param [Float] frequency The frequency each node have to be set (need to be lesser or equal than the physical core frequency). If the frequency is included in ]0,1] it'll be interpreted as a percentage of the physical core frequency, otherwise the frequency will be set to the specified number
      # @return [Hash] The virtual CPU description (see {file:files/resources_desc.md#CPU0 Resource Description - VCPU})
      def vcpu_create(vnodename, corenb=1, frequency=1.0)
        desc = { :corenb => corenb, :frequency => frequency }
        post_json("/vnodes/#{URI.escape(vnodename)}/cpu", { :desc => desc })
      end

      # Update a virtual CPU on the virtual node
      # @note This setting works on-the-fly (i.e. even if the virtual node is already running)
      # @param [String] vnodename The name of the virtual node
      # @param [Float] frequency The frequency each node have to be set (need to be lesser or equal than the physical core frequency). If the frequency is included in ]0,1] it'll be interpreted as a percentage of the physical core frequency, otherwise the frequency will be set to the specified number
      # @return [Hash] The virtual CPU description (see {file:files/resources_desc.md#CPU0 Resource Description - VCPU})
      def vcpu_update(vnodename, frequency)
        desc = { :frequency => frequency }
        put_json("/vnodes/#{URI.escape(vnodename)}/cpu", { :desc => desc })
      end

      # Removing a virtual CPU on the virtual node
      #
      # @param [String] vnodename The name of the virtual node
      # @return [Hash] The virtual CPU description (see {file:files/resources_desc.md#CPU0 Resource Description - VCPU})
      def vcpu_remove(vnodename)
        delete_json("/vnodes/#{URI.escape(vnodename)}/cpu")
      end

      # Retrive information about a virtual node CPU
      #
      # @return [Hash] The virtual CPU description (see {file:files/resources_desc.md#CPU0 Resource Description - VCPU})
      def vcpu_info(vnodename)
        get_json("/vnodes/#{URI.escape(vnodename)}/cpu")
      end

      # Set up the filesystem of a virtual node
      #
      # @param [String] vnodename The name of the virtual node
      # @param [Hash] desc Hash structured as described in {file:files/resources_desc.md#File_System0 Resource Description - VFilesystem}.
      # @return [Hash] The virtual Filesystem description (see {file:files/resources_desc.md#File_System0 Resource Description - VFilesystem})
      def vfilesystem_create(vnodename,desc)
        post_json("/vnodes/#{URI.escape(vnodename)}/filesystem", { :desc => desc })
      end

      # Update the filesystem of a virtual node
      #
      # @param [String] vnodename The name of the virtual node
      # @param [Hash] desc Hash structured as described in {file:files/resources_desc.md#File_System0 Resource Description - VFilesystem}.
      # @return [Hash] The virtual Filesystem description (see {file:files/resources_desc.md#File_System0 Resource Description - VFilesystem})
      def vfilesystem_update(vnodename,desc)
        put_json("/vnodes/#{URI.escape(vnodename)}/filesystem", { :desc => desc })
      end

      # Retrieve informations about a virtual node filesystem
      #
      # @param [String] vnodename The name of the virtual node
      # @return [Hash] The virtual node filesystem informations
      def vfilesystem_info(vnodename)
        get_json("/vnodes/#{URI.escape(vnodename)}/filesystem")
      end

      # Retrieve compressed image (tgz) of the filesystem of a node.
      #
      # @param [String] vnodename The name of the virtual node
      # @param [String] target The path to save the file, if not specified, the current directory is used
      # @return [String] The path where the compressed image was retrieved
      def vfilesystem_image(vnodename,target = '.')
        raise Lib::ResourceNotFoundError, File.dirname(target) unless File.exists?(File.dirname(target))
        if File.directory?(target)
          target = File.join(target,"#{vnodename}-fsimage.tar.gz")
        end
        content = get_content("/vnodes/#{URI.escape(vnodename)}/filesystem/image")

        File.open(target, 'w') { |f|
          f.syswrite(content)
        }
        target
      end

      # Create a new virtual network
      #
      # @param [String] name The name of the virtual network (unique)
      # @param [String] address The address (CIDR format: 10.0.8.0/24) the virtual network will work with
      # @return [Hash] The virtual network description (see {file:files/resources_desc.md#Virtual_Networks Resource Description - VNetworks})
      def vnetwork_create(name, address)
        post_json("/vnetworks", { :name => name, :address => address })
      end

      # Remove a virtual network, that will disconnect every virtual node connected on it and remove it's virtual routes.
      #
      # @param [String] vnetname The name of the virtual network
      # @return [Hash] The virtual network description (see {file:files/resources_desc.md#Virtual_Networks Resource Description - VNetworks})
      def vnetwork_remove(vnetname)
        delete_json("/vnetworks/#{URI.escape(vnetname)}")
      end

      # Retrieve informations about a virtual network
      #
      # @param [String] vnetname The name of the virtual network
      # @return [Hash] The virtual network description (see {file:files/resources_desc.md#Virtual_Networks Resource Description - VNetworks})
      def vnetwork_info(vnetname)
        get_json("/vnetworks/#{URI.escape(vnetname)}")
      end

      # Remove every virtual network
      #
      # @return [Array] Array of virtual network descriptions (see {file:files/resources_desc.md#Virtual_Networks Resource Description - VNetworks})
      def vnetworks_remove()
        delete_json("/vnetworks")
      end

      # Retrieve informations about every virtual network currently set on the platform
      # @return [Array] Array of virtual network descriptions (see {file:files/resources_desc.md#Virtual_Networks Resource Description - VNetworks})
      def vnetworks_info()
        get_json("/vnetworks")
      end

      # Create a new virtual route between two virtual networks ("<dstnet> is accessible from <srcnet> using <gateway>")
      #
      # @param [String] srcnet The name of the source virtual network
      # @param [String] dstnet The name of the destination virtual network
      # @param [String] gateway The name of the virtual node to use as gateway (this node have to be connected on both of the previously mentioned networks), the node is automatically set in gateway mode
      # @return [Hash] The virtual route description (see {file:files/resources_desc.md#Virtual_Routes Resource Description - VRoutes})
      def vroute_create(srcnet,dstnet,gateway)
        post_json("/vnetworks/#{URI.escape(srcnet)}/routes",
          { :destnetwork => dstnet, :gatewaynode => gateway })
      end

      # Create all possible virtual routes between all the virtual networks, automagically choosing the virtual nodes to use as gateways
      #
      # @return [Array] Array of virtual route descriptions (see {file:files/resources_desc.md#Virtual_Routes Resource Description - VRoutes})
      def vroute_complete()
        post_json("/vnetworks/routes/complete", { })
      end

      # Create an set a platform with backup data
      # @param [String] format The input data format
      # @param [String] data Data structured as described in {file:files/resources_desc.md#Virtual_Node}.
      # @return [Hash] The virtual platform description (see {file:files/resources_desc.md#Virtual_Platform Resource Description - VPlatform})

      def vplatform_create(data,format = 'JSON')
        post_json("/vplatform", { 'format' => format, 'data' => data })
      end

      # Get the full description of the platform
      #
      # @param [String] format The wished output format
      # @return [String] The description in the wished format
      def vplatform_info(format = 'JSON')
        get_json("/vplatform/#{format}")
      end

      protected

      # Check if there was an error in the REST request
      # @private
      # ==== Attributes
      # * +result+ the result header (see RestClient)
      # * +response+ the response header (see RestClient)
      # ==== Returns
      # The response header object if no problems found (String)
      # ==== Exceptions
      # * +ClientError+ if the HTTP status returned performing the request is not HTTP_OK, the Exception object contains the description of the error
      def check_error(result,response)
        case result.code.to_i
          when HTTP_STATUS_OK
          else
            begin
              body = JSON.parse(response)
            rescue JSON::ParserError
              body = response
            end
            raise Lib::ClientError.new(
              result.code.to_i,
              response.headers[:x_application_error_code],
              body
            )
        end
        return response
      end

      # Check if there was an error related to the network connection
      # @private
      # ==== Attributes
      # * +route+ the route path to access (REST)
      # ==== Returns
      # ==== Exceptions
      # * +InvalidParameterError+ if given path is not available on the server
      # * +UnavailableResourceError+ if for one reason or another the host is unreachable
      def check_net(route)
        @@semreq.acquire
        begin
          yield
        rescue RestClient::RequestFailed
          raise Lib::InvalidParameterError, "#{@serverurl}#{route}"
        rescue RestClient::Exception, Errno::ECONNREFUSED, Timeout::Error, \
          RestClient::RequestTimeout, Errno::ECONNRESET, SocketError
          raise Lib::UnavailableResourceError, @serverurl
        ensure
          @@semreq.release
        end
      end

      # Convert a Ruby structure to something that RestClient can digest
      # @param [Hash] h hash whose values will be flattened
      # @return new hash with its values converted to string or simple types
      def flatten_hash(h)
        h2 = { }
        h.each_pair { |k, v|
          f = CLASSMAP.select { |i, j| v.is_a?(i) }.to_a.first
          raise "Dictionary contains an element of unsupported class #{v.class}." if f.nil?
          h2[k] = f.last.call(v)
        }
        h2
      end

      # Send raw request and handle possible errors
      # @private
      # @param [Symbol] method HTTP method
      # @param [String] route route where the resource is located
      # @param [Hash] data optional content to post/put/delete/get
      # @param [Boolean] convert to json or not
      # @return JSON or raw content
      def raw_request(method, route, data = {}, json = true)
        data = flatten_hash(data)
        ret = json ? {} : ''
        check_net(route) do
          @resource[route].send(method, data) { |response, request, result|
            ret = check_error(result, response)
            ret = JSON.parse(ret) if json
          }
        end
        ret
      end

      def post_json(route, data)
        raw_request(:post, route, data)
      end

      def put_json(route, data)
        raw_request(:put, route, data)
      end

      def get_json(route)
        raw_request(:get, route)
      end

      def delete_json(route)
        raw_request(:delete, route)
      end

      def get_content(route)
        raw_request(:get, route, data = { }, json = false)
      end

    end

  end
end
