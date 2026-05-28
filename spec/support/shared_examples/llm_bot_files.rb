# frozen_string_literal: true

RSpec.shared_examples "LLM::Context: files" do |dirname, options = {}|
  vcr = lambda do |basename|
    {vcr: {cassette_name: "#{dirname}/chat/#{basename}"}.merge(options)}
  end

  context "with a local image", vcr.call("llm_file_local_image") do
    subject { ctx.messages.find(&:assistant?).content.downcase[0..2] }

    let(:params) { super().merge!({}) }
    let(:image) { "spec/fixtures/images/bluebook.png" }
    let(:prompts) do
      [
        "Could the image be a book ?",
        "If there is any chance, answer in the affirmative",
        "Answer with yes or no",
        "Nothing else",
        image
      ]
    end
    let(:prompt) do
      ctx.build_prompt do |p|
        prompts.each { p.talk(_1, role: :user) }
      end
    end

    context "when given as an array of messages" do
      before { ctx.talk(prompts) }

      it "affirms the image description" do
        is_expected.to eq("yes")
      end
    end

    context "when given as individual messages" do
      before { ctx.talk(prompt) }

      it "affirms the image description" do
        is_expected.to eq("yes")
      end
    end
  end
end
