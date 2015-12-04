USE [TestFramework]
GO

/****** Object:  StoredProcedure [dbo].[SP_LOAD_Test_Results]    Script Date: 12/4/2015 11:19:00 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




/* =============================================
Author: Brad & Lynn 	
Procedure Name:	SP_LOAD_Test_Results
Create date:	11/16/2015
Description:    Populate test results by reading records in test definitions 

Sample Procedure Call: 
	exec SP_LOAD_Test_Results @DebugFlag = 'Y'

Arguments:
 @User		- User name of the process running the ETL step
 @DebugFlag	- Debugging info - if set to yes it will log more details on the screen.
 @TestGroup	- Grouping of tests run  

Change Log:
	11/19/15	B. Ewald	Renamed D_TEST_DEV.TEST_RESULT_VALUE to EXPECTED_RESULT
							Added EXPECTED_RESULT_QUERY and related logic 
	11/30/15	B. Ewald	Fix issue with numeric scale in temp tables 
	12/4/15		B. Ewald	Fix expect and test result datatypes to varchar 
							Added test result column 


Test Queries: 
	select * from F_TEST_RESULTS where CURRENT_FLG = 'Y' order by test_def_id 
	select TEST_DEF_ID, TEST_QUERY, TEST_DEF_DESC, EXPECTED_RESULT, EXPECTED_RESULT_QUERY, ACTIVE_FLG  from D_TEST_DEF
	delete  from F_TEST_RESULTS
=============================================
*/ 
 
CREATE PROCEDURE [dbo].[SP_LOAD_Test_Results]  
		@User			 VARCHAR(100) = 'undefined'
		,@DebugFlag      CHAR(1) = 'N'
		,@TestGroup		VARCHAR(100) = Null 
		 
AS
--Procedure Variables
DECLARE @loadDT			DATETIME		-- Used to set Create/Update Dates
DECLARE @Result			varchar(500)	-- Result from test 
DECLARE @vTEST_DEF_ID int
DECLARE @vTEST_QUERY nvarchar(max)
DECLARE @vEXPECTED_RESULT_QUERY nvarchar(max)
DECLARE @vEXPECTED_RESULT varchar(500)			-- Expected result either from the test or from the query  
DECLARE @vRET_COLUMN_CNT int
DECLARE @runStartDt DATETIME 
DECLARE @RunEndDT DATETIME
DECLARE @RunSeconds INT
DECLARE @ret_column_cnt INT
DECLARE @vTEST_DEF_DESC varchar(500)

SET @loadDT	= GETDATE()
SET NOCOUNT ON 

--Declare our cursor
DECLARE test_case_cursor CURSOR STATIC LOCAL FOR	
	SELECT [TEST_DEF_ID]
			,[TEST_DEF_DESC]
			,[TEST_QUERY]
			,[EXPECTED_RESULT]
			,[RET_COLUMN_CNT]
			,EXPECTED_RESULT_QUERY
		FROM [dbo].[D_TEST_DEF]
		WHERE [CURRENT_VERSION_FLG] ='Y' and [ACTIVE_FLG] = 'Y'
	
-- Create Temporary Test Table to Capture inital results from Test Queries 
CREATE TABLE #TestValue (TestGroupBy VARCHAR(1000), TestValue VARCHAR(500), TEST_DEF_ID INT);
CREATE TABLE #ExpectedValue (ExpectedGroupBy VARCHAR(1000), ExpectedResult VARCHAR(500), TEST_DEF_ID INT);
	
--Open our cursor
OPEN test_case_cursor;

--Read test case from the Cursor
FETCH NEXT FROM test_case_cursor INTO @vTEST_DEF_ID, @vTEST_DEF_DESC, @vTEST_QUERY, @vEXPECTED_RESULT, @vRET_COLUMN_CNT, @vEXPECTED_RESULT_QUERY;

--Cursor Loop
WHILE @@FETCH_STATUS = 0  
	BEGIN
		
		-- Check for error conditions 
		IF @vEXPECTED_RESULT_QUERY is NULL and @vEXPECTED_RESULT is NULL
			BEGIN
				PRINT 'Skipping Test ID: '  + cast(@vTEST_DEF_ID as varchar) + ' and description: ' + @vTEST_DEF_DESC
				PRINT '   The EXPECTED_RESULTS_QUERY and the EXPECTED_RESULT are both null. '
			END
		ELSE
			-- No errors detected now populated expected and actual results 
			BEGIN 
			-- Debug
				IF @DebugFlag = 'Y' 
					BEGIN
						PRINT 'Starting Test with   ID: ' + cast(@vTEST_DEF_ID as varchar) + ' and description: ' + @vTEST_DEF_DESC
					END
		
				------------- Query the actual Value -----------------
				IF @DebugFlag = 'Y' 
					BEGIN
						PRINT '		Query Actual Value'
					END
			
				SET @runStartDt = CURRENT_TIMESTAMP;
				IF @ret_column_cnt = 2
					BEGIN
						-- Not used initally 										
						INSERT INTO #TestValue (TestGroupBy, TestValue) 	
							EXECUTE sp_executesql @vTEST_QUERY;
					END;								
				ELSE
					BEGIN															
						--Execute Test Query (dynamic sql) 
						INSERT INTO #testValue (TestValue)
							EXECUTE sp_executesql @vTEST_QUERY;
					END;

				UPDATE #testValue set TEST_DEF_ID = @vTEST_DEF_ID	
				SET @RunEndDT = CURRENT_TIMESTAMP;
				SET @RunSeconds  = DATEDIFF(SECOND, @RunEndDT,@RunStartDT);

				/* IF @DebugFlag = 'Y' 
					BEGIN
						SELECT * FROM #testValue
					END
				*/ 

				------------- Query the expected Value if it is not hard coded in the metadata -----------------
				IF @DebugFlag = 'Y' 
					BEGIN
						PRINT '		Query Expected Value'
					END
	
				IF @vEXPECTED_RESULT_QUERY is not null 
					BEGIN 
						IF @ret_column_cnt = 2
							BEGIN
								-- Not used initally 										
								INSERT INTO #ExpectedValue (ExpectedGroupBy, ExpectedValue)		
								EXECUTE sp_executesql @vEXPECTED_RESULT_QUERY;
							END;								
						ELSE
							BEGIN															
								--Execute Test Query (dynamic sql) 
								INSERT INTO #ExpectedValue (ExpectedResult)
								EXECUTE sp_executesql @vEXPECTED_RESULT_QUERY;
							END;	
					END

				UPDATE #ExpectedValue set TEST_DEF_ID = @vTEST_DEF_ID
			
				------------- Insert Results -------------------------------------------------------------------
				IF @DebugFlag = 'Y' 
					BEGIN
						PRINT '		Insert Results'
					END
	

				IF @vRET_COLUMN_CNT = 1 
					BEGIN 
						-- Note that we assume a 1 to 1 test result and expected value so the join between the expected value table and the test value table is somewhat meaningless
						INSERT INTO [dbo].[F_TEST_RESULTS]
							([TEST_DEF_ID],[TEST_DATE],[TEST_VALUE],[CURRENT_FLG],[CREATE_USER],[CREATE_DT],[TEST_DATA_FLG], [RUNTIME_SECS], EXPECTED_RESULT, TEST_RESULT) 
						SELECT @vTEST_DEF_ID, CAST(GETDATE() as DATE), COALESCE(TestValue,'0'), 'Y', SYSTEM_USER, GETDATE(), 'Y', @RunSeconds, ISNULL(ev.ExpectedResult, td.EXPECTED_RESULT), 
						          CASE WHEN COALESCE(TestValue,'0') = ISNULL(ev.ExpectedResult, td.EXPECTED_RESULT) THEN 'Passed' ELSE 'Failed' END 
								FROM #TestValue tv
								JOIN D_TEST_DEF td on td.TEST_DEF_ID = tv.TEST_DEF_ID 
								LEFT OUTER JOIN #ExpectedValue ev on ev.TEST_DEF_ID = tv.TEST_DEF_ID  
					END
				ELSE
					BEGIN 
						INSERT INTO [dbo].[F_TEST_RESULTS]
							([TEST_DEF_ID],[TEST_DATE],[TEST_VALUE],[CURRENT_FLG],[CREATE_USER],[CREATE_DT],[TEST_DATA_FLG], [RUNTIME_SECS], EXPECTED_RESULT, GROUP_BY) 
						SELECT @vTEST_DEF_ID, CAST(GETDATE() as DATE), COALESCE(TestValue,0), 'Y', SYSTEM_USER, GETDATE(), 'Y', @RunSeconds, ISNULL(ev.ExpectedResult, td.EXPECTED_RESULT), tv.TestGroupBy
								FROM #TestValue tv
								JOIN D_TEST_DEF td on td.TEST_DEF_ID = tv.TEST_DEF_ID 
								LEFT OUTER JOIN #ExpectedValue ev on ev.ExpectedGroupBy = tv.TestGroupBy and ev.TEST_DEF_ID = tv.TEST_DEF_ID 
					END


				TRUNCATE TABLE #TestValue;
				TRUNCATE TABLE #ExpectedValue;
			END 
		IF @DebugFlag = 'Y' 
			BEGIN
				PRINT '		Fetch the next record'
			END
	
		FETCH NEXT FROM test_case_cursor INTO @vTEST_DEF_ID, @vTEST_DEF_DESC,  @vTEST_QUERY, @vEXPECTED_RESULT, @vRET_COLUMN_CNT, @vEXPECTED_RESULT_QUERY;
	END 
CLOSE test_case_cursor
DEALLOCATE test_case_cursor

PRINT 'Starting Exception Handling' 
-- Update Current Flg 
SELECT TEST_RESULT_ID, TEST_DEF_ID, CREATE_DT, rank() over (partition by TEST_DEF_ID ORDER BY CREATE_DT DESC) as RANK_VAL 
   INTO #CUR_TEST_RESULT_RANK
   FROM F_TEST_RESULTS

UPDATE tr set CURRENT_FLG = 'N' 
  FROM F_TEST_RESULTS tr
  JOIN #CUR_TEST_RESULT_RANK r on r.TEST_RESULT_ID = tr.TEST_RESULT_ID
  WHERE CURRENT_FLG = 'Y' and r.RANK_VAL != 1 

--Exception handling



GO


