require 'savon'

class SdpOperations

    # Intiialize details required to communicate with Safaricom SDP server
    @@sdp_server_address = Rails.application.secrets.sdp_server_address
    @@sdp_server_port = Rails.application.secrets.sdp_server_port
    @@sdp_sp_id = Rails.application.secrets.sdp_sp_id.to_s
    @@sdp_username = Rails.application.secrets.sdp_username
    @@sdp_password = Rails.application.secrets.sdp_password

    @@timestamp_string = Time.now.strftime("%Y%m%d%H%M%S")
    @@hashed_sdp_password = Digest::MD5.hexdigest(@@sdp_sp_id + @@sdp_password + @@timestamp_string)

    @@gateway_server_address = Rails.application.secrets.gateway_server_address
    @@gateway_port = Rails.application.secrets.gateway_port.to_s

    # SendSms operation used to send messages to Safaricom SDP server
    # for termination to mobile subscriber 
    def self.send_sms(message_text, destinations, sender, service_id, correlator, linkid = nil)
	destinations.uniq!
	soap_header = self.soap_header(service_id, linkid)
	soap_namespaces = self.soap_namespaces
	
    	destinations.each_slice(Rails.application.secrets.number_recipients_per_request) do |destinations_slice|
	    soap_message = self.soap_message(destinations_slice, sender, message_text, correlator)
	    soap_client = Savon.client do  
		wsdl "wsdl/parlayx_sms_send_service_2_2.wsdl"
		namespaces soap_namespaces
		env_namespace :soapenv
		namespace_identifier :loc
		pretty_print_xml :true
		log true
		logger Rails.logger
		log_level :debug
		soap_header soap_header
	    end

	    begin
		retries ||= 0
		initial_delay_in_s = 1
		response = soap_client.call(:send_sms, message: soap_message)
	    rescue Savon::HTTPError, Savon::SOAPFault => error
		# Wait a little bit before retrying
		sleep(retries * initial_delay_in_s)
		if (retries += 1) < 10 
		    retry
		else
		    raise error
		end
	    end
	end
    end

    private
    def self.soap_namespaces
	return { 
            "xmlns:v2" => "http://www.huawei.com.cn/schema/common/v2_1" 
        }
    end

    def self.soap_header(service_id, linkid)
	 return  { 
           "v2:RequestSOAPHeader": {
                "v2:sp_id": @@sdp_sp_id,
                "v2:sp_password": @@hashed_sdp_password,
                "v2:service_id": service_id,
                "v2:time_stamp": @@timestamp_string #,
                # "v2:linkid": linkid,
                # "v2:OA": destination,
                # "v2:FA": destination
           }.merge( linkid.present? ? {
                 "v2:linkid": linkid,
                 "v2:OA": destination,
                 "v2:FA": destination
             } : {})
        }
    end

    def self.soap_message(destinations, sender, message_text, correlator)
	return {
            "loc:addresses": destinations.collect { |destination| "tel:" + destination },
            "loc:sender_name": sender,
            "loc:message": message_text,
            "loc:receipt_request": {
            endpoint: "http://" + @@gateway_server_address + ":" + @@gateway_port + "/delivery_notifications",
                interface_name: "SmsNotification",
                correlator: correlator
	    }
	}
    end
end
