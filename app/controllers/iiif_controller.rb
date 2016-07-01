require 'iiif/presentation'
class IiifController < ApplicationController
  def collections
    site_collection = IIIF::Presentation::Collection.new
    site_collection['@id'] = url_for({:controller => 'iiif', :action => 'collections', :only_path => false})
    site_collection.label = "IIIF resources avaliable on the FromThePage installation at #{Rails.application.config.action_mailer.default_url_options[:host]}"
    
    Collection.where(:restricted => false).each do |collection|
      iiif_collection = iiif_collection_from_collection(collection,false)      
      
      site_collection.collections << iiif_collection
    end
    
    render :text => site_collection.to_json(pretty: true), :content_type => "application/json"
  end
    
  def collection
    iiif_collection = iiif_collection_from_collection(@collection,true)      
    
    render :text => iiif_collection.to_json(pretty: true), :content_type => "application/json"
  end


    
  def manifest
    work_id =  params[:id]


    work = Work.find work_id
    seed = { 
              '@id' => url_for({:controller => 'iiif', :action => 'manifest', :id => work.id, :only_path => false}), 
              'label' => work.title
            }
    manifest = IIIF::Presentation::Manifest.new(seed)
    manifest.label = work.title
    manifest.description = work.description unless work.description.blank?
    manifest.within = iiif_collection_id_from_collection(work.collection)
    sequence = iiif_sequence_from_work_id(work_id)
    manifest.sequences << sequence

    render :text => manifest.to_json(pretty: true), :content_type => "application/json"
  end

  def canvas
    render :text => canvas_from_page(@page).to_json(pretty: true), :content_type => "application/json"
    
  end
  
  def list
    type = params[:annotation_type]
    annotation_list = IIIF::Presentation::AnnotationList.new
    annotation_list['@id'] = url_for({:controller => 'iiif', :action => 'list', :page_id => @page.id, :annotation_type => type, :only_path => false})

    annotation = iiif_annotation_by_type(@page.id,type)

    annotation_list.resources << annotation
    render :text => annotation_list.to_json(pretty: true), :content_type => "application/json"
  end
  
  def sequence
    work_id = @work.id
    sequence = iiif_sequence_from_work_id(work_id)
    render :text => sequence.to_json(pretty: true), :content_type => "application/json" 
  end

  def annotation
    page_id = params[:page_id]
    type = params[:annotation_type]
    annotation = iiif_annotation_by_type(page_id,type)
    annotation['@id'] = url_for({:controller => 'iiif', :action => 'annotation', :page_id => @page.id, :annotation_type => type, :only_path => false})
    render :text => annotation.to_json(pretty: true), :content_type => "application/json" 
  end
    
private
  def iiif_annotation_by_type(page_id, type)
    case type
    when 'transcript'
      annotation = IIIF::Presentation::Annotation.new
      page = Page.find page_id
      annotation['on'] = region_from_page(@page)
      annotation.resource = IIIF::Presentation::Resource.new({'@id' => "plaintext_export_for_#{@page.id}", '@type' => "cnt:ContentAsText"})
      annotation.resource["format"] =  "text/plain"
    
      doc = Nokogiri::XML(@page.xml_text.gsub(/<\/p>/, "</p>\n\n").gsub("<lb/>", "\n"))
      no_tags = doc.text

      annotation.resource["chars"] = no_tags
    when 'translation'
      #do something
      annotation = IIIF::Presentation::Annotation.new
      page = Page.find page_id
      annotation['on'] = region_from_page(@page)
      annotation.resource = IIIF::Presentation::Resource.new({'@id' => "translation_export_for_#{@page.id}", '@type' => "cnt:ContentAsText"})
      annotation.resource["format"] =  "text/plain"
    
      doc = Nokogiri::XML(@page.xml_translation.gsub(/<\/p>/, "</p>\n\n").gsub("<lb/>", "\n"))
      no_tags = doc.text

      annotation.resource["chars"] = no_tags
    when 'facsimile'
      annotation = IIIF::Presentation::Annotation.new
      page = Page.find page_id
      annotation.resource = iiif_create_image_resource(page)
      annotation['on'] = region_from_page(@page)
    when type.match(/comment/)  #starts with comment?
      #do something
    end
    annotation
  end

  def iiif_image_annotation_from_work_id(work_id)
    annotation
  end
 
  def iiif_sequence_from_work_id(work_id)
    sequence = IIIF::Presentation::Sequence.new
    sequence['@id'] = url_for({:controller => 'iiif', :action => 'sequence', :work_id => work_id, :sequence_name => 'default', :only_path => false})
    sequence.label = 'Pages'
    work=Work.find work_id
    work.pages.each do |page|
      sequence.canvases << canvas_from_page(page)
    end   

    sequence
  end

  def iiif_collection_id_from_collection(collection)
    url_for({ :controller => 'iiif', :action => 'collection', :collection_id => collection.id, :only_path => false })
  end

  def iiif_collection_from_collection(collection,depth)
    iiif_collection = IIIF::Presentation::Collection.new
    iiif_collection.label = collection.title
    iiif_collection['@id'] = iiif_collection_id_from_collection(collection)
  
    if depth == true   
      collection.works.each do |work|
        unless work.ia_work
          seed = { 
                    '@id' => url_for({:controller => 'iiif', :action => 'manifest', :id => work.id, :only_path => false}), 
                    'label' => work.title
                }
          manifest = IIIF::Presentation::Manifest.new(seed)
          manifest.label = work.title
        
          iiif_collection.manifests << manifest            
        end
      end
    end
    iiif_collection  
  end

  def canvas_id_from_page(page)
    url_for({ :controller => 'iiif', :action => 'canvas', :page_id => page.id, :work_id => page.work.id, :only_path => false })
  end
  
  def region_from_page(page)
    canvas_id_from_page(page) + "#xywh=0,0,#{page.base_width},#{page.base_height}"  
  end

  def iiif_create_image_resource(page)
    image_resource = IIIF::Presentation::ImageResource.create_image_api_image_resource(
      {
        :service_id => "#{url_for(:root)}image-service/#{page.id}", 
        :resource_id => "#{url_for(:root)}image-service/#{page.id}/full/full/0/native.jpg",
        :height => page.base_height,
        :width => page.base_width,
        :profile => 'http://library.stanford.edu/iiif/image-api/1.1/compliance.html#level2',
                
       })
       
    image_resource.service['@context'] = 'http://iiif.io/api/image/1/context.json'
    image_resource
  end

  def canvas_from_page(page)
    annotation = IIIF::Presentation::Annotation.new
    annotation.resource = iiif_create_image_resource(page)
    
    canvas = IIIF::Presentation::Canvas.new
    canvas.label = page.title
    canvas.width = page.base_width
    canvas.height = page.base_height
    canvas['@id'] = canvas_id_from_page(page)
    
    annotation['on'] = canvas['@id']
    annotation['@id'] = "#{url_for(:root)}image-service/#{page.id}"
    canvas.images << annotation
    
    unless page.source_text.blank?
      annotation_list = IIIF::Presentation::AnnotationList.new
      annotation_list['@id'] = url_for({:controller => 'iiif', :action => 'list', :work_id => page.work_id, :page_id => page.id, :only_path => false})
      canvas.other_content << annotation_list
    end
    canvas    
  end

  
end
