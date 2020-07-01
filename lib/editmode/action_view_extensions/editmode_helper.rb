module Editmode
  module ActionViewExtensions
    module EditmodeHelper

      require 'httparty'

      def api_version
        # Todo Add Header Version
      end

      def api_root_url
        ENV["EDITMODE_OVERRIDE_API_URL"] || "https://api.editmode.com"
      end

      def chunk_collection(collection_identifier, **options)
        branch_params = params[:em_branch_id].present? ? "branch_id=#{params[:em_branch_id]}" : ""
        branch_id = params[:em_branch_id].presence
        tags = options[:tags].presence || []
        limit = options[:limit].presence

        begin 
          url_params = { 
            :collection_identifier => collection_identifier,
            :branch_id => branch_id,
            :limit => limit,
            :tags => tags
          }.to_query

          url = URI(api_root_url)
          url.path = '/chunks'
          url.query = url_params

          response = HTTParty.get(url)

          raise "No response received" unless response.code == 200
          chunks = response["chunks"]

          return chunks
        rescue => error
          puts error 
          return []
        end
      end

      def chunk_field_value(parent_chunk_object, custom_field_identifier,options={})

        begin 
          chunk_identifier = parent_chunk_object["identifier"]
          custom_field_item = parent_chunk_object["content"].detect {|f| f["custom_field_identifier"] == custom_field_identifier }
        
          if custom_field_item.present?
            render_chunk_content(
              custom_field_item["identifier"],
              custom_field_item["content"],
              custom_field_item["chunk_type"],
              { parent_identifier: chunk_identifier }.merge(options)
            )
          end
        rescue => errors
          puts errors
          content_tag(:span, "&nbsp".html_safe) 
        end
      
      end

      def render_chunk_content(chunk_identifier,chunk_content,chunk_type,options={})

        begin 
          # Always sanitize the content!!
          chunk_content = ActionController::Base.helpers.sanitize(chunk_content)
          
          css_class = options[:class]

          if chunk_type == "image"
            display_type = "image"
          else 
            display_type = options[:display_type] || "span"
          end

          chunk_data = { :chunk => chunk_identifier, :chunk_editable => false }

          if options[:parent_identifier].present?
            chunk_data.merge!({parent_identifier: options[:parent_identifier]})
          end

          case display_type
          when "span"
            if chunk_type == "rich_text"
              content_tag("em-span", :class => css_class, :data => chunk_data ) do
                chunk_content.html_safe
              end
            else
              content_tag("em-span", :class => css_class, :data => chunk_data.merge!({:chunk_editable => true}) ) do
                chunk_content
              end
            end
          when "image"
            image_tag(chunk_content, :data => chunk_data, :class => css_class) 
          end
        rescue => errors
          puts errors
          content_tag("em-span", "&nbsp".html_safe) 
        end

      end

      def chunk_display(label,identifier,options={},&block)
        branch_id = params[:em_branch_id]
        # This method should never show an error. 
        # If anything goes wrong fetching content
        # We should just show blank content, not
        # prevent the page from loading.
        begin
          branch_params = branch_id.present? ? "branch_id=#{branch_id}" : ""
          cache_identifier = "chunk_#{identifier}#{branch_id}"
          url = "#{api_root_url}/chunks/#{identifier}?#{branch_params}"
          cached_content_present = Rails.cache.exist?(cache_identifier)

          if !cached_content_present
            response = HTTParty.get(url)
            response_received = true if response.code == 200
          end

          if !cached_content_present && !response_received
            raise "No response received"
          else
            
            chunk_content = Rails.cache.fetch(cache_identifier) do  
              response['content']
            end

            chunk_type = Rails.cache.fetch("#{cache_identifier}_type") do  
              response['chunk_type']
            end

            render_chunk_content(identifier,chunk_content,chunk_type, options)

          end

        rescue => error
          # Show fallback content by default
          return content_tag("em-span", &block) if block_given?
          # Otherwise show a span with no content to 
          # maintain layout
          content_tag("em-span", "&nbsp".html_safe) 
        end

      end

      alias_method :chunk, :chunk_display

      def variable_parse!(content, variables, values)
        tokens = content.scan(/\{{(.*?)\}}/)
        if tokens.any?
          tokens.flatten! 
          tokens.each do |token|
            token_value = values[token.to_sym] || variables[token] || ""
            sanitized_value = ActionController::Base.helpers.sanitize(token_value)

            content.gsub!("{{#{token}}}", sanitized_value)
          end
        end

        content
      end

      def no_response_received(id = "")
        "Sorry, we can't find a chunk using this identifier: \"#{id}\". This can happen if you've deleted a chunk on editmode.com or if your local cache is out of date. If it persists, try running Rails.cache clear."
      end
      
      def require_field_id
        "Field ID or Field Name is required to retrieve a collection item"
      end
    end
  end
end
