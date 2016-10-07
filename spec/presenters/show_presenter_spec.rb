# frozen_string_literal: true

RSpec.describe Blacklight::ShowPresenter do
  include Capybara::RSpecMatchers
  let(:view_context) { double(search_state: search_state) }
  let(:config) { Blacklight::Configuration.new }

  subject { presenter }
  let(:presenter) { described_class.new(document, view_context, config) }
  let(:parameter_class) { ActionController::Parameters }
  let(:params) { parameter_class.new }
  let(:search_state) { Blacklight::SearchState.new(params, config) }

  let(:document) do
    SolrDocument.new(id: 1,
                     'link_to_facet_true' => 'x',
                     'link_to_facet_named' => 'x',
                     'qwer' => 'document qwer value',
                     'mnbv' => 'document mnbv value')
  end

  describe "link_rel_alternates" do
    before do
      class MockDocument
        include Blacklight::Solr::Document
      end

      module MockExtension
         def self.extended(document)
           document.will_export_as(:weird, "application/weird")
           document.will_export_as(:weirder, "application/weirder")
           document.will_export_as(:weird_dup, "application/weird")
         end
         def export_as_weird ; "weird" ; end
         def export_as_weirder ; "weirder" ; end
         def export_as_weird_dup ; "weird_dup" ; end
      end

      MockDocument.use_extension(MockExtension)

      def mock_document_app_helper_url *args
        solr_document_url(*args)
      end

      allow(view_context).to receive(:polymorphic_url) do |_, opts|
        "url.#{opts[:format]}"
      end
    end

    let(:document) { MockDocument.new(id: "MOCK_ID1") }

    context "with no arguments" do
      subject { presenter.link_rel_alternates }

      it "generates <link rel=alternate> tags" do
        tmp_value = Capybara.ignore_hidden_elements
        Capybara.ignore_hidden_elements = false
        document.export_formats.each_pair do |format, spec|
          expect(subject).to have_selector("link[href$='.#{ format  }']") do |matches|
            expect(matches).to have(1).match
            tag = matches[0]
            expect(tag.attributes["rel"].value).to eq "alternate"
            expect(tag.attributes["title"].value).to eq format.to_s
            expect(tag.attributes["href"].value).to eq mock_document_app_helper_url(document, format: format)
          end
        end
        Capybara.ignore_hidden_elements = tmp_value
      end

      it { is_expected.to be_html_safe }
    end

    context "with unique: true" do
      subject { presenter.link_rel_alternates(unique: true) }

      it "respects unique: true" do
        tmp_value = Capybara.ignore_hidden_elements
        Capybara.ignore_hidden_elements = false
        expect(subject).to have_selector("link[type='application/weird']", count: 1)
        Capybara.ignore_hidden_elements = tmp_value
      end
    end

    context "with exclude" do
      subject { presenter.link_rel_alternates(unique: true) }
      it "excludes formats from :exclude" do
        tmp_value = Capybara.ignore_hidden_elements
        Capybara.ignore_hidden_elements = false
        expect(subject).to_not have_selector("link[href$='.weird_dup']")
        Capybara.ignore_hidden_elements = tmp_value
      end
    end
  end

  describe "#render_field?" do
    before do
      allow(view_context).to receive_messages(should_render_field?: true, document_has_value?: true)
    end

    it "is true" do
      expect(presenter.render_field?(double)).to be true
    end

    it "is false if the document doesn't have a value for the field" do
      allow(view_context).to receive_messages(document_has_value?: false)
      expect(presenter.render_field?(double)).to be false
    end

    it "is false if the configuration has the field disabled" do
      allow(view_context).to receive_messages(should_render_field?: false)
      expect(presenter.render_field?(double)).to be false
    end
  end

  describe "field_value" do
    let(:config) do
      Blacklight::Configuration.new.configure do |config|
        config.add_show_field 'qwer'
        config.add_show_field 'asdf', :helper_method => :render_asdf_document_show_field
        config.add_show_field 'link_to_facet_true', :link_to_facet => true
        config.add_show_field 'link_to_facet_named', :link_to_facet => :some_field
        config.add_show_field 'highlight', :highlight => true
        config.add_show_field 'solr_doc_accessor', :accessor => true
        config.add_show_field 'explicit_accessor', :accessor => :solr_doc_accessor
        config.add_show_field 'explicit_array_accessor', :accessor => [:solr_doc_accessor, :some_method]
        config.add_show_field 'explicit_accessor_with_arg', :accessor => :solr_doc_accessor_with_arg
      end
    end

    it 'html-escapes values' do
      field = config.show_fields['asdf']
      value = subject.field_value field, value: '<b>val1</b>'
      expect(value).to eq '&lt;b&gt;val1&lt;/b&gt;'
    end

    it 'joins multivalued valued fields' do
      field = config.show_fields['asdf']
      value = subject.field_value field, value: ['<a', 'b']
      expect(value).to eq '&lt;a and b'
    end

    it 'joins multivalued valued fields' do
      field = config.show_fields['asdf']
      value = subject.field_value field, value: ['a', 'b', 'c']
      expect(value).to eq 'a, b, and c'
    end

    it "checks for an explicit value" do
      expect(view_context).to_not receive(:render_asdf_document_show_field)
      field = config.show_fields['asdf']
      value = subject.field_value field, :value => 'val1'
      expect(value).to eq 'val1'
    end

    it "checks for a helper method to call" do
      allow(view_context).to receive(:render_asdf_document_show_field).and_return('custom asdf value')
      field = config.show_fields['asdf']
      value = subject.field_value field
      expect(value).to eq 'custom asdf value'
    end

    it "checks for a link_to_facet" do
      allow(view_context).to receive(:search_action_path).and_return('/foo')
      allow(view_context).to receive(:link_to).with("x", '/foo').and_return('bar')
      field = config.show_fields['link_to_facet_true']
      value = subject.field_value field
      expect(value).to eq 'bar'
    end

    it "checks for a link_to_facet with a field name" do
      allow(view_context).to receive(:search_action_path).and_return('/foo')
      allow(view_context).to receive(:link_to).with("x", '/foo').and_return('bar')
      field = config.show_fields['link_to_facet_named']
      value = subject.field_value field
      expect(value).to eq 'bar'
    end

    context "when no highlight field is available" do
      before do
        allow(document).to receive(:has_highlight_field?).and_return(false)
      end
      let(:field) { config.show_fields['highlight'] }
      let(:value) { subject.field_value field }
      it "is blank" do
        expect(value).to be_blank
      end
    end

    it "checks for a highlighted field" do
      allow(document).to receive(:has_highlight_field?).and_return(true)
      allow(document).to receive(:highlight_field).with('highlight').and_return(['<em>highlight</em>'.html_safe])
      field = config.show_fields['highlight']
      value = subject.field_value field
      expect(value).to eq '<em>highlight</em>'
    end

    it 'respects the HTML-safeness of multivalued highlight fields' do
      allow(document).to receive(:has_highlight_field?).and_return(true)
      allow(document).to receive(:highlight_field).with('highlight').and_return(['<em>highlight</em>'.html_safe, '<em>other highlight</em>'.html_safe])
      field = config.show_fields['highlight']
      value = subject.field_value field
      expect(value).to eq '<em>highlight</em> and <em>other highlight</em>'
    end

    it "checks the document field value" do
      field = config.show_fields['qwer']
      value = subject.field_value field
      expect(value).to eq 'document qwer value'
    end

    it "calls an accessor on the solr document" do
      allow(document).to receive_messages(solr_doc_accessor: "123")
      field = config.show_fields['solr_doc_accessor']
      value = subject.field_value field
      expect(value).to eq "123"
    end

    it "calls an explicit accessor on the solr document" do
      allow(document).to receive_messages(solr_doc_accessor: "123")
      field = config.show_fields['explicit_accessor']
      value = subject.field_value field
      expect(value).to eq "123"
    end

    it "calls an explicit array-style accessor on the solr document" do
      allow(document).to receive_message_chain(:solr_doc_accessor, some_method: "123")
      field = config.show_fields['explicit_array_accessor']
      value = subject.field_value field
      expect(value).to eq "123"
    end

    it "calls an accessor on the solr document with the field as an argument" do
      allow(document).to receive(:solr_doc_accessor_with_arg).with('explicit_accessor_with_arg').and_return("123")
      field = config.show_fields['explicit_accessor_with_arg']
      value = subject.field_value field
      expect(value).to eq "123"
    end
  end

  describe "#heading" do
    it "falls back to an id" do
      allow(document).to receive(:[]).with('id').and_return "xyz"
      expect(subject.heading).to eq document.id
    end

    it "returns the value of the field" do
      config.show.title_field = :x
      allow(document).to receive(:has?).with(:x).and_return(true)
      allow(document).to receive(:[]).with(:x).and_return("value")
      expect(subject.heading).to eq "value"
    end

    it "returns the first present value" do
      config.show.title_field = [:x, :y]
      allow(document).to receive(:has?).with(:x).and_return(false)
      allow(document).to receive(:has?).with(:y).and_return(true)
      allow(document).to receive(:[]).with(:y).and_return("value")
      expect(subject.heading).to eq "value"
    end
  end

  describe "#html_title" do
    it "falls back to an id" do
      allow(document).to receive(:[]).with('id').and_return "xyz"
      expect(subject.html_title).to eq document.id
    end

    it "returns the value of the field" do
      config.show.html_title_field = :x
      allow(document).to receive(:has?).with(:x).and_return(true)
      allow(document).to receive(:fetch).with(:x, nil).and_return("value")
      expect(subject.html_title).to eq "value"
    end

    it "returns the first present value" do
      config.show.html_title_field = [:x, :y]
      allow(document).to receive(:has?).with(:x).and_return(false)
      allow(document).to receive(:has?).with(:y).and_return(true)
      allow(document).to receive(:fetch).with(:y, nil).and_return("value")
      expect(subject.html_title).to eq "value"
    end
  end

  describe '#field_values' do
    context 'for a field with the helper_method option' do
      let(:field_name) { 'field_with_helper' }
      let(:field_config) { config.add_facet_field 'field_with_helper', helper_method: 'render_field_with_helper' }
      let(:document) do
        SolrDocument.new(id: 1, 'field_with_helper' => 'value')
      end

      it "checks call the helper method with arguments" do
        allow(view_context).to receive(:render_field_with_helper) do |*args|
          args.first
        end

        render_options = { a: 1 }

        options = subject.send(:field_values, field_config, a: 1)

        expect(options).to include :document, :field, :value, :config, :a
        expect(options[:document]).to eq document
        expect(options[:field]).to eq 'field_with_helper'
        expect(options[:value]).to eq ['value']
        expect(options[:config]).to eq field_config
        expect(options[:a]).to eq 1
      end
    end
  end
end

