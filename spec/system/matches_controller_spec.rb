require "rails_helper"

RSpec.describe MatchesController, type: :system do
  let!(:user) { create(:user, :from_paris) }
  let!(:second_user) { create(:user) }
  let!(:partner) { create(:partner) }
  let!(:center) { create(:vaccination_center, :from_paris) }
  let!(:campaign) { create(:campaign, vaccination_center: center) }
  let!(:match_confirmation_token) { "abcd" }
  let!(:match) { create(:match, user: user, vaccination_center: center, match_confirmation_token: match_confirmation_token, expires_at: 1.hour.since, campaign: campaign) }

  subject { visit match_path(match_confirmation_token, source: "sms") }

  describe "GET show" do
    context "with a valid match" do
      it "confirms the match only when all inputs are filled" do
        subject
        expect(page).to have_text("est disponible près de chez vous")
        expect(page).to have_text("Je confirme le RDV")
        expect(page).to have_text("Distance du centre de vaccination")
        expect(page).to have_field("user_firstname", with: user.firstname)
        expect(page).to have_field("user_lastname", with: user.lastname)

        fill_in :user_firstname, with: user.firstname
        fill_in :user_lastname, with: ""
        check :confirm_age
        check :confirm_name
        check :confirm_distance
        check :confirm_hours
        click_on("Je confirme le RDV")
        expect(page).to have_text("Vous devez renseigner votre")

        fill_in :user_firstname, with: ""
        fill_in :user_lastname, with: user.lastname
        check :confirm_age
        check :confirm_name
        check :confirm_distance
        check :confirm_hours
        click_on("Je confirme le RDV")
        expect(page).to have_text("Vous devez renseigner votre")

        fill_in :user_firstname, with: user.firstname
        fill_in :user_lastname, with: user.lastname
        check :confirm_age
        check :confirm_name
        check :confirm_distance
        check :confirm_hours
        click_on("Je confirme le RDV")
        expect(page).not_to have_text("Vous devez renseigner votre")
        expect(page).to have_text("Votre rendez-vous est confirmé")
        expect(page).to have_text("Adresse du centre de vaccination")
        expect(page).to have_text(center.address)
        match.reload
        expect(match.sms_first_clicked_at).to_not eq(nil)
      end
    end

    context "with a confirmed match" do
      before do
        match.update_column("confirmed_at", Time.now)
      end
      it "it says dispo confirmée" do
        subject
        expect(page).to have_text("Votre rendez-vous est confirmé")
        expect(page).to have_text("Adresse du centre de vaccination")
        expect(page).to have_text(center.address)
      end
    end

    context "with an expired match" do
      before do
        match.update_column("expires_at", 5.minutes.ago)
      end

      it "it says delai dépassé" do
        subject
        expect(page).to have_text("Le délai de confirmation est dépassé")
      end
    end

    context "with an anonymized user" do
      before { user.anonymize! }
      it "redirects to root" do
        subject
        expect(page).to have_current_path(root_path)
      end
    end

    context "with an invalid token" do
      it "redirects to root" do
        visit match_path("invalid-token")
        expect(page).to have_current_path(root_path)
      end
    end

    context "when the campaign has no #remaining_doses" do
      # confirm all the slots
      before do
        while campaign.remaining_doses > 0
          create(:match, :confirmed, campaign: campaign)
        end
      end

      it "handle the user's disappointment gracefully" do
        visit match_path(match_confirmation_token)

        expect(page).to have_text("Mince 😔, toutes les doses disponibles ont déjà été réservées")
        expect(page).not_to have_text("Je confirme le RDV")
      end
    end

    context "when another match has been confirmed while I was already browsing the match page" do
      # confirm all the slots but one
      before do
        while campaign.remaining_doses > 1
          create(:match, :confirmed, campaign: campaign)
        end
      end

      it "handle the user's disappointment gracefully" do
        already_confirmed_count = Match.where(confirmation_failed_reason: "Match::AlreadyConfirmedError").count
        visit match_path(match_confirmation_token)

        # A volunteer confirms a few seconds before me
        # while I'm browsing the match show page
        create(:match, :confirmed, campaign: campaign)

        fill_in :user_firstname, with: generate(:firstname)
        fill_in :user_lastname, with: generate(:lastname)
        check :confirm_age
        check :confirm_name
        check :confirm_distance
        check :confirm_hours
        click_on("Je confirme le RDV")
        expect(page).to have_text("Mince 😔, toutes les doses disponibles ont déjà été réservées")
        Match.where(confirmation_failed_reason: "Match::AlreadyConfirmedError").count == already_confirmed_count + 1
      end
    end

    context "when the old campaign is canceled but another campaign has been created" do
      before do
        campaign.canceled!
        create(:campaign, vaccination_center: center)
      end

      it "does not redirect the user to the new campaign" do
        # When match auto-creation is prodded, switch "does not redirect" to "redirects"
        visit match_path(match_confirmation_token)
        expect(page).not_to have_text("Bonne nouvelle, nous avons trouvé une autre dose")
        # When match auto-creation is prodded, switch "not_to" to "to"
      end
    end

    context "when the old campaign is canceled but another campaign has been created with match" do
      before do
        campaign.canceled!
        new_campaign = create(:campaign, vaccination_center: center)
        create(:match, user: user, vaccination_center: center, expires_at: 1.hour.since, campaign: new_campaign)
      end

      it "redirects the user to the new campaign with match" do
        visit match_path(match_confirmation_token)
        expect(page).to have_text("Bonne nouvelle, nous avons trouvé une autre dose")
      end
    end

    context "when 10 old matches are canceled but another campaign has been created" do
      before do
        campaign.canceled!
        9.times.each do |i|
          other_campaign = create(:campaign, vaccination_center: center)
          create(:match, user: user, campaign: other_campaign)
          other_campaign.canceled!
        end
        create(:campaign, vaccination_center: center)
      end

      it "does not redirect the user to the new campaign" do
        visit match_path(match_confirmation_token)
        expect(page).not_to have_text("Bonne nouvelle, nous avons trouvé une autre dose")
      end
    end

    context "when the old campaign has no remaining doses but another campaign has been created" do
      before do
        while campaign.remaining_doses > 0
          create(:match, :confirmed, campaign: campaign)
        end
        create(:campaign, vaccination_center: center)
      end

      it "does not redirect the user to the new campaign" do
        # When match auto-creation is prodded, switch "does not redirect" to "redirects"
        visit match_path(match_confirmation_token)
        expect(page).not_to have_text("Bonne nouvelle, nous avons trouvé une autre dose")
        # When match auto-creation is prodded, switch "not_to" to "to"
      end
    end

    context "when the old campaign has no remaining doses but another campaign has been created with match" do
      before do
        while campaign.remaining_doses > 0
          create(:match, :confirmed, campaign: campaign)
        end
        new_campaign = create(:campaign, vaccination_center: center)
        create(:match, user: user, vaccination_center: center, expires_at: 1.hour.since, campaign: new_campaign)
      end

      it "redirects the user to the new campaign with match" do
        visit match_path(match_confirmation_token)
        expect(page).to have_text("Bonne nouvelle, nous avons trouvé une autre dose")
      end
    end
  end
end
