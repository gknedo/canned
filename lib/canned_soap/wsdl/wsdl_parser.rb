require 'xmlsimple'
require 'canned_soap/soap/soap'
require 'canned_soap/web/web_request_handler'
include CannedSoap::Soap
include CannedSoap::Web

module CannedSoap::Wsdl
	class WsdlParser
		# Parse the service wsdl to a +Wsdl+ object
		# Params :
		# +service+:: the url of the service
		def self.parse(service)
			@service = service
			wsdl_xml = get_serivce_data('wsdl')
			doc = XmlSimple.xml_in(wsdl_xml)

			res = Wsdl.new
			res.actions = get_soap_actions(doc)
			res.location_address = get_location_address(doc)
			res.target_namespace = doc['targetNamespace']

			res
		end

		# Return the target namespace of the last wsdl parser.
		# TODO: Remove this method and user tel +Wsdl+ it self to get the target namespace
		def self.target_namespace
			@@target_namespace
		end

		private
			# Return the service data for specified extension (wsdl, xsd=xsd0, etc)
			# Params:
			# +extension+:: the extension the query the service with (wsdl, xsd=xsd0, etc)
			def self.get_serivce_data(extension)
				uri = URI("#{@service}")

				res = get_web_response("#{@service}?#{extension}",
										{"Accept" => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
										 "Accept-Encoding" => 'gzip,deflate,sdch'})
				res.body
			end

			# ???
			def self.get_action_datacontact(action_name)
				if @xsd_namespace.nil?
					xsd0 = get_serivce_data('xsd=xsd0')
					doc = XmlSimple.xml_in(xsd0)

					import = doc['import']
					@xsd_namespace = (import.first['namespace'] unless import.nil?)
				end

				@xsd_namespace
			end

			# Return list of +SoapAction+
			# Params:
			# +doc+:: +Hash+ that represent the wsdl xml
			def self.get_soap_actions(doc)
				result = []

				@@target_namespace = doc['targetNamespace']
				should_read_from_xsd = !doc['types'].first['schema'].first['import'].nil?

				binding = doc['binding'].first
				binding['operation'].each do |opp|
					action = SoapAction.new

					action.name = opp['name']
					action.soap_action = opp['operation'].first['soapAction']
					action.parameters = get_action_params(action.name, doc, should_read_from_xsd)

					result << action
				end

				result
			end

			# Return the location address of the service
			# Params:
			# +doc+:: +Hash+ that represent the wsdl xml
			def self.get_location_address(doc)
				service = doc['service']
				location = service.first['port'].first['address'].first['location']

				location
			end

			# Return the parameters that the soap actiop requires as list of +SoapParamter+ objects
			# Params :
			# +action_name+:: the name of the soap action
			# +doc+:: hash the represent the WSDL
			# +should_read_from_xsd+:: boolean that indicates whether it should read the parameters from the wsdl or imported xsd
			def self.get_action_params(action_name,doc,should_read_from_xsd)
				if(should_read_from_xsd)
					get_action_params_from_xsd(action_name)
				else
					get_action_params_from_wsdl(action_name,doc)
				end
			end

			# Parse the soap action element in the wsdl and return the parameters that the soap actiop requires as list of +SoapParamter+ objects
			# Params:
			# +action_name+:: the name of the soap action
			# +doc+:: hash the represent the WSDL
			def self.get_action_params_from_wsdl(action_name, doc)
				#puts opp['input'].first
				if @schema.nil?
					@schema =  doc['types'].first['schema'].first
				end

				action_element = @schema['element'].select{|e| e['name'] == action_name}.first
				action_params_elements = action_element['complexType'].first['sequence'].first['element']

				action_params_elements.map do |element|
					SoapParamter.parse(element) do |param|
						param.nullable = ['minOccurs'] == 0
					end
				end
			end

			# Parse the imported xsd and return the parameters that the soap actiop requires as list of +SoapParamter+ objects
			# Params:
			# +action_name+:: the name of the soap action
			def self.get_action_params_from_xsd(action_name)
				if @elements.nil?
					#@elements = {}
					xsd0 = get_serivce_data('xsd=xsd0')
					doc = XmlSimple.xml_in(xsd0)

					@elements = doc['element']

					# the page dose not have imported shceme
					return nil if @elements.nil?
				end

				element = @elements.select{|e| e['name'] == action_name}.first
				sequence = element['complexType'].first['sequence'].first

				return [] if sequence['element'].nil?
				sequence['element'].map do |e|
					SoapParamter.parse(e) do |param|
						param.nullable = e['nillable']
						namespace_element = e.select{|key,value| key.match(/xmlns(.*)/)}.first
						(param.namespace = namespace_element[1]) unless namespace_element.nil?
					end
				end
			end
	end
end
