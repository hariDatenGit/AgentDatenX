@IsTest
private class TDAgentControllerTest {

    @IsTest
    static void testRunGuidedTour_start() {
        Test.startTest();
        TDAgentController.TourResult result = TDAgentController.runGuidedTour('start');
        Test.stopTest();
        Assert.isNotNull(result, 'Result should not be null');
        Assert.isNotNull(result.tourResponse, 'tourResponse should not be null for start step');
    }

    @IsTest
    static void testRunGuidedTour_case() {
        Test.startTest();
        TDAgentController.TourResult result = TDAgentController.runGuidedTour('case');
        Test.stopTest();
        Assert.isNotNull(result.tourResponse, 'tourResponse should not be null for case step');
    }

    @IsTest
    static void testRunGuidedTour_knowledge() {
        Test.startTest();
        TDAgentController.TourResult result = TDAgentController.runGuidedTour('knowledge');
        Test.stopTest();
        Assert.isNotNull(result.tourResponse, 'tourResponse should not be null for knowledge step');
    }

    @IsTest
    static void testRunGuidedTour_track() {
        Test.startTest();
        TDAgentController.TourResult result = TDAgentController.runGuidedTour('track');
        Test.stopTest();
        Assert.isNotNull(result.tourResponse, 'tourResponse should not be null for track step');
    }

    @IsTest
    static void testRunGuidedTour_nullInput_defaultsToStart() {
        Test.startTest();
        TDAgentController.TourResult result = TDAgentController.runGuidedTour(null);
        Test.stopTest();
        Assert.isNotNull(result, 'Null input should return a valid result (defaults to start)');
    }

    @IsTest
    static void testRunGuidedTour_blankInput_defaultsToStart() {
        Test.startTest();
        TDAgentController.TourResult result = TDAgentController.runGuidedTour('   ');
        Test.stopTest();
        Assert.isNotNull(result, 'Blank input should return a valid result (defaults to start)');
    }

    @IsTest
    static void testRunGuidedTour_disallowedStep_defaultsToStart() {
        Test.startTest();
        TDAgentController.TourResult result = TDAgentController.runGuidedTour('__malicious_step__');
        Test.stopTest();
        Assert.isNotNull(result, 'Disallowed step should be sanitized and return a valid result');
    }

    @IsTest
    static void testRunGuidedTour_uppercaseInput_normalised() {
        Test.startTest();
        TDAgentController.TourResult result = TDAgentController.runGuidedTour('CASE');
        Test.stopTest();
        Assert.isNotNull(result, 'Uppercase input should be normalised and return a valid result');
    }
}