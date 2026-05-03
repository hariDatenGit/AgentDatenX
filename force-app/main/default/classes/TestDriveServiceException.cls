/**
 * Domain exception for Test Drive scheduling services.
 * Use for validation errors and sanitized unexpected errors in TestDriveService and related selectors.
 *
 * Note: Do not redeclare base Exception constructors; Apex provides them implicitly.
 */
public class TestDriveServiceException extends Exception { }