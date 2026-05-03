/**
 * TDAgentController
 * Guest-accessible Apex controller for the Test Drive Agentforce widget.
 * Invokes the TD_Guided_Tour autolaunched flow and returns structured output.
 *
 * Security: with sharing enforced. No SOQL. No DML. Flow handles all data ops.
 */
public with sharing class TDAgentController {

    public class TourResult {
        @AuraEnabled public String tourResponse;
        @AuraEnabled public String nextStepUrl;
    }

    /**
     * Invokes the TD_Guided_Tour flow for a given tour step.
     * Called by the tdAgentWidget LWC via @salesforce/apex.
     *
     * @param tourStep  One of: start | case | knowledge | track | feedback
     * @return          TourResult with tourResponse text and nextStepUrl
     */
    @AuraEnabled(cacheable=false)
    public static TourResult runGuidedTour(String tourStep) {
        String safeStep = String.isBlank(tourStep) ? 'start' : tourStep.toLowerCase().trim();

        // Allowlist to prevent arbitrary flow invocation
        Set<String> allowedSteps = new Set<String>{ 'start', 'case', 'knowledge', 'track', 'feedback' };
        if (!allowedSteps.contains(safeStep)) {
            safeStep = 'start';
        }

        Map<String, Object> inputs = new Map<String, Object>{ 'tourStep' => safeStep };

        try {
            Flow.Interview interview = Flow.Interview.createInterview('TD_Guided_Tour', inputs);
            interview.start();

            TourResult result    = new TourResult();
            result.tourResponse  = (String) interview.getVariableValue('tourResponse');
            result.nextStepUrl   = (String) interview.getVariableValue('nextStepUrl');
            return result;

        } catch (Exception e) {
            TourResult errorResult    = new TourResult();
            errorResult.tourResponse  = 'I\'m having a moment — please try again or click "Talk to a human" for direct support.';
            errorResult.nextStepUrl   = '/testdrive/s/contact';
            return errorResult;
        }
    }
}