require "rails_helper"

RSpec.describe "Editing with an editor", js: true do
  let(:template) { file_fixture("article_published.txt").read }
  let(:user) do
    u = create(:user)
    u.setting.update(editor_version: "v1")
    u
  end
  let(:article) { create(:article, user: user, body_markdown: template) }
  let(:svg_image) { file_fixture("300x100.svg").read }

  before do
    allow(Settings::General).to receive(:main_social_image).and_return("https://dummyimage.com/800x600.jpg")
    allow(Settings::General).to receive(:logo_png).and_return("https://dummyimage.com/800x600.png")
    allow(Settings::General).to receive(:mascot_image_url).and_return("https://dummyimage.com/800x600.jpg")
    allow(Settings::General).to receive(:suggested_tags).and_return("coding, beginners")
    sign_in user
  end

  def update_editor_body(content)
    within("#article-form") do
      field = if page.has_field?("article_body_markdown", visible: :all, disabled: :all)
                find_field("article_body_markdown", visible: :all, disabled: :all)
              else
                find("textarea[id*='article_body_markdown'], textarea[id*='textarea-for']", visible: :all)
              end

      page.execute_script(
        "arguments[0].value = arguments[1]; arguments[0].dispatchEvent(new Event('input', { bubbles: true }));",
        field,
        content,
      )
    end
  end

  it "user previews their changes" do
    visit "/#{user.username}/#{article.slug}/edit"
    update_editor_body(template.gsub("Suspendisse", "Yooo"))
    click_button("Preview")
    expect(page).to have_text("Yooo")
  end

  it "user updates their post" do
    visit "/#{user.username}/#{article.slug}/edit"
    update_editor_body(template.gsub("Suspendisse", "Yooo"))
    click_button("Save changes")
    expect(page).to have_text("Yooo")
  end

  it "user unpublishes their post" do
    visit "/#{user.username}/#{article.slug}/edit"
    update_editor_body(template.gsub("true", "false"))
    click_button("Save changes")
    expect(page).to have_text("Unpublished Post.")
  end

  context "when user edits too many articles" do
    let(:rate_limit_checker) { RateLimitChecker.new(user) }

    before do
      # avoid hitting new user rate limit check
      allow(user).to receive(:created_at).and_return(1.week.ago)
      allow(RateLimitChecker).to receive(:new).and_return(rate_limit_checker)
      allow(rate_limit_checker).to receive(:limit_by_action)
        .with(:article_update)
        .and_return(true)
    end

    it "displays a rate limit warning", :flaky, js: true do
      visit "/#{user.username}/#{article.slug}/edit"
      update_editor_body(template.gsub("Suspendisse", "Yooo"))
      click_button "Save changes"
      expect(page).to have_text("Rate limit reached")
    end
  end
end
