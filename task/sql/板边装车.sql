USE [OrBitX]
GO
/****** Object:  StoredProcedure [dbo].[Txn_BatchInCarSMT]    Script Date: 05/07/2015 08:50:29 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[Txn_BatchInCarSMT]
@I_Sender				nvarchar(200)='',			--客户端执行按钮
@I_ReturnMessage		nvarchar(max)='' output,	--返回的信息,支持多语言
@I_ExceptionFieldName	nvarchar(100)='' output,	--向客户端报告引起冲突的字段
@I_LanguageId			char(1)='1',				--客户端传入的语言ID
@I_PlugInCommand		varchar(5)='',				--插件命令
@I_OrBitUserId			char(12)='',				--用户ID
@I_OrBitUserName		nvarchar(100)='',			--用户名
@I_ResourceId			char(12)='',				--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName			nvarchar(100)='',			--资源名
@I_PKId					char(12) = '',				--主键
@I_SourcePKId			char(12)='',				--执行拷贝时传入的源主键  
@I_ParentPKId			char(12)='',				--父级主键
@I_Parameter			nvarchar(100)='',			--插件参数	

@MOId CHAR(12)=NULL,             --工单Id
@CarSN NVARCHAR(50)=NULL,        --车号SN
@ParentSN NVARCHAR(50)=NULL,     --板边条码
@MakeUpCount INT=0,              --当前传入连板数量
@SNList NVARCHAR(MAX)=NULL,      --单板条码列表,多个用逗号隔开
@IsComplete BIT=NULL OUTPUT,	 --是否已民自动关闭车号(当装车数量达到设置数量时会自动关闭车号)
@InCarQty INT=0 OUTPUT, --已装车数量
@Flag INT=NULL --装车标识(0：扫描校验车号	1：扫描校验板边条码		2：扫描校验单板条码		3：强制装车		4：清空未关闭的车号)
AS
BEGIN
	SET NOCOUNT ON
	SET @SNList=UPPER(@SNList)
	IF ISNULL(@MOId,'')=''
	 BEGIN
		SET @I_ReturnMessage='ServerMessage:请选择工单!'
		RETURN -1
	 END
	IF ISNULL(@CarSN,'')=''
	 BEGIN
		SET @I_ReturnMessage='ServerMessage:请输入车号!'
		RETURN -1
	 END
	IF @Flag=2 AND (@SNList IS NULL OR LEN(@SNList)<1 OR @SNList=',')
	 BEGIN
		SET @I_ReturnMessage='ServerMessage:请扫描单板SN!'
		RETURN -1
	 END
	if exists( select *  from DataChainLoadCar where CarSN=ISNULL(@CarSN,'n/a') and ProdentryStatus  is not null )
 	begin
		SET @I_ReturnMessage='ServerMessage:此车号已装有QC批退单板，不能再装正常板，'+CHAR(10)+'请更换没有批退板的车号进行板边条码装车．'
		RETURN -1
 	end 
	 
	 
	DECLARE @CustomerId CHAR(12)
	DECLARE @WOSN NVARCHAR(50)
	DECLARE @IsHuaWeiCustomer BIT
	DECLARE @ProductId CHAR(12)
	DECLARE @MOName NVARCHAR(50)
	DECLARE @MOItemId CHAR(12)
	DECLARE @return_value INT
	DECLARE @CarQty INT
	SELECT @CustomerId=MO.CustomerId,@MOName=MOName,@WOSN=MO.WOSN,@ProductId=ProductId FROM dbo.MO WITH(NOLOCK) WHERE MOId=@MOID
    BEGIN
		EXEC dbo.txn_IsHuaWeiCustomer 
				@CustomerId = @CustomerId, -- char(12)
				@MOID=@MOID,
				@IsHuaWeiCustomer = @IsHuaWeiCustomer OUTPUT -- bit
    END
    SELECT @CarQty=BoxQty FROM dbo.Product  WITH(NOLOCK) WHERE ProductId=@ProductId
    IF @CarQty IS NULL OR @CarQty<1
     BEGIN
		SET @I_ReturnMessage='ServerMessage:请先维护产品的装箱数量!'
		RETURN -1
	 END
    
	 
	DECLARE @CarMOItemLotId CHAR(12)
	DECLARE @_SpecificationId CHAR(12)='SPE1000000DS'
	DECLARE @CarBrandStatus NVARCHAR(50)
	DECLARE @RowCount INT
	SET @IsComplete=0
	BEGIN --先校验车辆信息
		SELECT @CarMOItemLotId=MOItemLotId,@CarBrandStatus=BrandStatus FROM dbo.MOItemLot  WITH(NOLOCK) WHERE MOId=@MOId AND SNType='CartonSN' AND LotSN=@CarSN
		IF @CarMOItemLotId IS NULL
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:车号['+@CarSN+']错误!'
			RETURN -1
		 END
		IF ISNULL(@CarBrandStatus,'')='1'
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:车号['+@CarSN+']已关闭,不能再扫描操作!'
			RETURN -1
		 END
	END
	
    IF @Flag=0  --扫描校验车号
     BEGIN
		SET @RowCount=0
		SELECT @RowCount=COUNT(1) FROM DataChainLoadCar  WITH(NOLOCK) WHERE CarSN=@CarSN
		SET @InCarQty=@RowCount
		SET @I_ReturnMessage='ServerMessage:车号['+@CarSN+']正确'+CASE WHEN ISNULL(@RowCount,0)>1 THEN '(已装'+CAST(@RowCount AS NVARCHAR(10))+'个产品)' ELSE '' END+'!'
		RETURN 0
     END
     
    DECLARE @SNTable TABLE
    (
		LotId CHAR(12),
		SN NVARCHAR(50),
		DataChainId CHAR(12),
		DatachainLoadCarID CHAR(12),
		ProductionLot NVARCHAR(50),
		SpecificationId CHAR(12),
		RowNum INT IDENTITY(1,1)
    )
    
    INSERT INTO @SNTable(SN)
    SELECT parameter_Value AS SN FROM dbo.ConvertParameterToTable(@SNList,',')
    
    DECLARE @LotId CHAR(12)
    DECLARE @SpecificationId CHAR(12)
    DECLARE @SpecificationName NVARCHAR(50)
    DECLARE @LotMOId CHAR(12)
    DECLARE @ParentMakeUpCount INT
    DECLARE @SNCount INT
    DECLARE @WorkflowId CHAR(12)
    DECLARE @WorkcenterId CHAR(12)
    DECLARE @WorkflowStepId CHAR(12)
    
    SELECT @SNCount=COUNT(1) FROM @SNTable
    select @WorkcenterId=WorkcenterId from [Resource] where ResourceId=@I_ResourceId
     
    IF @Flag=1 OR @Flag=2--扫描校验板边条码(扫描单板时也必须校验板边条码)
     BEGIN
		IF ISNULL(@ParentSN,'')=''
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:请扫描板边条码!'
			RETURN -1
		 END
		SELECT @LotId=LotId,@SpecificationId=SpecificationId,@LotMOId=MOId,@ParentMakeUpCount=ISNULL(MakeUpCount,0),@MOItemId=MOItemId,@WorkflowId=WorkflowId,
		@WorkflowStepId=WorkflowStepId FROM dbo.Lot  WITH(NOLOCK) WHERE LotSN=@ParentSN AND ProductionLot=@ParentSN
		IF @LotId IS NULL
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:板边条码['+@ParentSN+']未启动!'
			RETURN -1
		 END
		IF ISNULL(@LotMOId,'')!=@MOId
		 BEGIN
			SET @MOName=NULL
			SELECT @MOName=MOName FROM dbo.MO  WITH(NOLOCK) WHERE MOId=@LotMOId
			SET @I_ReturnMessage='ServerMessage:板边条码['+@ParentSN+']对应的工单为['+ISNULL(@MOName,'N/A')+'],请检查!'
			RETURN -1
		 END
		IF NOT EXISTS(SELECT 1 FROM dbo.MOItemLot  WITH(NOLOCK) WHERE MOId=@MOId AND SNType='SN' AND LotSN=@ParentSN)
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:板边条码['+@ParentSN+']错误,请检查!'
			RETURN -1
		 END
		IF ISNULL(@SpecificationId,'')!=@_SpecificationId
		 BEGIN
			SET @SpecificationName=NULL
			SELECT @SpecificationName=SpecificationName FROM dbo.SpecificationRoot  WITH(NOLOCK) WHERE DefaultSpecificationId=@SpecificationId
			SET @I_ReturnMessage='ServerMessage:板边条码['+@ParentSN+']位于规程['+ISNULL(@SpecificationName,'N/A')+']处,请检查!' 
			RETURN -1
		 END
		IF EXISTS(SELECT 1 FROM dbo.Lot  WITH(NOLOCK) WHERE ProductionLot=@ParentSN AND LotSN!=@ParentSN)
		 BEGIN
			SET @SpecificationName=NULL
			SELECT @SpecificationName=SpecificationName FROM dbo.SpecificationRoot  WITH(NOLOCK) WHERE DefaultSpecificationId=@SpecificationId
			SET @I_ReturnMessage='ServerMessage:板边条码['+@ParentSN+']已绑定单板SN,请检查!' 
			RETURN -1
		 END
		IF @Flag=1
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:板边条码['+@ParentSN+']正确,对应的连板数为['+CAST(@ParentMakeUpCount AS NVARCHAR(50))+']!' 
			RETURN 0
		 END
		IF @Flag=2
		 BEGIN
			IF @SNCount=0
			 BEGIN
				SET @I_ReturnMessage='ServerMessage:请扫描单板SN!' 
				RETURN -1
			 END
			IF @MakeUpCount!=@SNCount
			 BEGIN
				SET @I_ReturnMessage='ServerMessage:板边SN的个数为['+CAST(@SNCount AS NVARCHAR(10))+']不等于设置的连板数['+CAST(@MakeUpCount AS NVARCHAR(10))+']!' 
				RETURN -1
			 END
		 END
     END
     
    DECLARE  @PKDataSet  TABLE   
	( 
		RowNum INT ,
		PkID CHAR(12)
	)
	DECLARE @SN NVARCHAR(50)
	DECLARE @i INT=1
	DECLARE @IsAutoCloseCar BIT=0
	IF @Flag=2  --启动单板条码
	 BEGIN
		UPDATE @SNTable SET ProductionLot=Lot.ProductionLot,
			                SpecificationId=Lot.SpecificationId,
			                LotId=Lot.LotId
		FROM @SNTable LEFT JOIN dbo.Lot  WITH(NOLOCK)  ON [@SNTable].SN = dbo.Lot.LotSN
		
		SET @SN=NULL
		SELECT TOP 1 @SN=SN FROM @SNTable WHERE LotId IS NOT NULL AND LotId!='' AND  ProductionLot IS NOT NULL AND ProductionLot!=''
		IF @SN IS NOT NULL
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:单板条码['+@SN+']已启动!'
			RETURN -1
		 END
		 
		SELECT TOP 1 @SN=SN FROM @SNTable WHERE LotId IS NOT NULL AND LotId!='' AND SpecificationId IS NOT NULL   AND SpecificationId!=@_SpecificationId
		IF @SN IS NOT NULL
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:单板条码['+@SN+']已启动!'
			RETURN -1
		 END
		 
		SELECT TOP 1 @SN=SN FROM @SNTable WHERE SN=ProductionLot
		IF @SN IS NOT NULL
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:条码['+@SN+']为板边条码,请确认!'
			RETURN -1
		 END
		 
		SELECT @SN=SN FROM @SNTable A WHERE NOT EXISTS(SELECT 1 FROM dbo.MOItemLot  WITH(NOLOCK) WHERE LotSN=A.SN AND MOId=@MOId AND SNType='PCBASN')
		IF @SN IS NOT NULL
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:单板条码['+@SN+']错误!'
			RETURN -1
		 END
		
		DECLARE @SNs NVARCHAR(MAX) 
		SET @SNs=''
		SELECT @SNs=@SNs+SN+',' FROM @SNTable WHERE LotId IS NULL
		IF LEN(@SNs)>0 AND @SNs!=','
		 BEGIN
			SET @SNs=LEFT(@SNs,LEN(@SNs)-1)
			--启动SN
			DECLARE @LotIdList NVARCHAR(MAX)
			EXEC @return_value=dbo.TxnBase_LotStart_Batch1 
				@I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
			    @I_PlugInCommand = @I_PlugInCommand, -- varchar(5)
			    @I_OrBitUserId = @I_OrBitUserId, -- char(12)
			    @I_ResourceId = @I_ResourceId, -- char(12)
			    @LotIdList = @LotIdList OUTPUT, -- nvarchar(max)
			    @LotList = @SNs, -- nvarchar(max)
			    @VendorLotSNList=@SNs,
			    @StartReasonId = 'URC1000000B7', -- char(12)
			    @ProductId = @ProductId, -- char(12)
			    @LotStatus = '1', -- char(1)
			    @Qty = 1, -- float
			    @ProductionLot = @ParentSN, -- varchar(20)
			    @MOId = @MOId, -- char(12)
			    @MOItemId = @MOItemId, -- char(12)
			    @WorkflowId = @WorkflowId, -- char(12),
			    @SNType='PCBASN',
			    @SpecificationId = @_SpecificationId -- char(12)
			IF @return_value!=0
			 BEGIN
				RETURN -1
			 END
			 
			DECLARE @ss NVARCHAR(50)
			DECLARE @DefectcodeSn NVARCHAR(50)
			DECLARE @PASS_FAIL_FLAG NVARCHAR(20)
			DECLARE tempCur CURSOR
			FOR
			SELECT SN FROM @SNTable  WHERE LotId IS NULL
			OPEN tempCur
			FETCH NEXT FROM tempCur INTO @ss
			WHILE @@fetch_status =0
			 BEGIN
				BEGIN TRY
					
					--SELECT TOP 1 @DefectcodeSn=DefectcodeSn FROM dbo.DataChainLoadCar  WITH(NOLOCK) WHERE LotSN=@ss ORDER BY Createdate DESC
					--对于用板边条码来目检的工作流中的板,不良数据在维修中抓取数据 by luoll 20141125
					SELECT TOP 1 @DefectcodeSn=UserCodeName FROM dbo.RepairHistory  WITH(NOLOCK)
					INNER JOIN dbo.UserCode WITH(NOLOCK) ON dbo.RepairHistory.ErrorCodeId = dbo.UserCode.UserCodeId 
					WHERE SubPCBA=@ss ORDER BY RepairHistory.Createdate DESC
					
					IF ISNULL(@DefectcodeSn,'')=''
					 BEGIN
						SET @PASS_FAIL_FLAG='P'
					 END
					ELSE
					 BEGIN
						SET @PASS_FAIL_FLAG='F'
					 END
					 
					EXEC dbo.Interface_HuaWei_IWIPLOTSTS4D 
				    @I_ReturnMessage=@I_ReturnMessage OUTPUT,
					@LOT_ID=@ss,
					@EMS_ORDER_ID=@MOName,
					@PASS_FAIL_FLAG=@PASS_FAIL_FLAG,
					@DEFECT_CODE=@DefectcodeSn,
					@MOTHER_LOT_ID=@ParentSN		--不良代码(如果有的话)
				END TRY
				BEGIN CATCH
					PRINT ERROR_MESSAGE()
					insert into CatchErooeLog(ProcName,ErooeCommad) values('Txn_BatchInCarSMT_Huawei',ISNULL(ERROR_MESSAGE(),'上传到华为记录表中失败')+ ' ' + ISNULL(@I_ReturnMessage,'')) -- add by ybj 20141017
				END CATCH 
				FETCH NEXT FROM tempCur INTO @ss
			 END
			CLOSE  tempCur
			DEALLOCATE tempCur
			
			UPDATE @SNTable SET LotId=B.parameter_Value,
				                ProductionLot=@ParentSN,
				                SpecificationId=@_SpecificationId
			FROM @SNTable  N
			INNER JOIN
			(
				SELECT parameter_Value,ROW_NUMBER()OVER(ORDER BY ISNULL('','')) AS RowNum FROM dbo.ConvertParameterToTable(@SNs,',') 
			)A ON N.SN=A.parameter_Value
			INNER JOIN
			(
				SELECT parameter_Value,ROW_NUMBER()OVER(ORDER BY ISNULL('','')) AS RowNum FROM dbo.ConvertParameterToTable(@LotIdList,',') 
			)B ON A.RowNum = B.RowNum
			WHERE N.LotId IS NULL						
		 END
		 
		 
		EXEC Txn_BanBianUnLoadToHW
		@MOId=@MOId,
		@ParentSN=@ParentSN
		 
		SET @SN=NULL
		SELECT TOP 1 @SN=LotSN FROM DataChainLoadCar  WITH(NOLOCK) WHERE LotID IN (SELECT LotId FROM @SNTable) AND  DefectcodeSn IS NULL AND ISNULL(QCCheckresult,1)<>0
		IF  @SN IS NOT NULL
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:单板条码['+@SN+']已装车!'
			RETURN -1
		 END
		--装车
		SELECT @WorkcenterId=WorkcenterId FROM dbo.Resource  WITH(NOLOCK) WHERE ResourceId=@I_ResourceId
		
		
		DELETE @PKDataSet  --删除主键表数据,表供下次使用
		INSERT INTO @PKDataSet 
		EXEC SysGetBatchObjectPKId @ObjectName='DataChain' ,@RowCount=@SNCount --取指定数量的Lot表主键id
		
		UPDATE @SNTable SET DataChainId=[@PKDataSet].PkID
		FROM @SNTable LEFT JOIN  @PKDataSet ON [@SNTable].RowNum = [@PKDataSet].RowNum 
		
		INSERT INTO DataChain (
				DataChainId,
				LotId,
				MOId,
				MOItemId,
				Qty,
				TxnCode,
				ProductId,
				UserId,
				WorkcenterId,
				ResourceId,
				ShiftId,
				SpecificationId,
				WorkflowStepId,
				PluginId
			)
		SELECT DataChainId,
			   LotId,
			   @MOId,
			   @MOItemId,
			   1,
			   'DC',
			   @ProductId,
			   @I_OrBitUserId,
			   @WorkcenterId,
			   @I_ResourceId,
			   '',
			   @_SpecificationId,
			   @WorkflowStepId,
			   @I_PlugInCommand
		FROM @SNTable
		
		
		DELETE @PKDataSet  --删除主键表数据,表供下次使用
		INSERT INTO @PKDataSet 
		EXEC SysGetBatchObjectPKId @ObjectName='DataChainLoadCar' ,@RowCount=@SNCount --取指定数量的Lot表主键id
		
		UPDATE @SNTable SET DatachainLoadCarID=[@PKDataSet].PkID
		FROM @SNTable LEFT JOIN  @PKDataSet ON [@SNTable].RowNum = [@PKDataSet].RowNum 
		
		INSERT INTO dbo.DataChainLoadCar
		        ( DatachainLoadCarID ,
		          DataChainID ,
		          MOID ,
		          LotID ,
		          LotSN ,
		          CarSN ,
		          QCCheckresult ,
		          ProdentryStatus ,
		          NSStatus ,
		          UserID ,
		          Createdate ,
		          DefectcodeSn
		        )
		SELECT DatachainLoadCarID,
			   DataChainID,
			   @MOId,
			   LotId,
			   SN,
			   @CarSN,
			   NULL,
			   NULL,
			   NULL,
			   @I_OrBitUserId,
			   GETDATE(),
			   NULL
		FROM @SNTable
		
		
		DECLARE @DataChainId CHAR(12)
		EXEC	[dbo].[TxnBase_DataChainMainLine]
					@DataChainId = @DataChainId OUTPUT,
					@TxnCode ='SMTSN',
					@I_PlugInCommand = @I_PlugInCommand,
					@I_OrBitUserId = @I_OrBitUserId,
					@I_ResourceId = @I_ResourceId,
					@LotId = @LotId,
					@MOID = @MOID,
					@ProductId = @productid,
					@Qty = @SNCount,
					@SpecificationId = @_SpecificationId,
					@WorkflowStepId=@WorkflowStepId,
					@UserComment='板边条码与单板条码绑定'
		
		DELETE 	DataChain_SMTSN_Binding WHERE lotid=@lotid	
		INSERT INTO DataChain_SMTSN_Binding
		(
			 DataChainId,
			 moid,
			lotid,
			SMTSN,
			createdate			
		)
		SELECT @DataChainId,@moid,@lotid, @ParentSN,GETDATE()
		
		
		DECLARE @SumINCount INT
		SELECT @SumINCount=COUNT(1) FROM DataChainLoadCar WHERE CarSN=@CarSN
		
		UPDATE dbo.Lot SET ProductionLot=@ParentSN WHERE LotId IN(SELECT LotId FROM @SNTable)
		SET @InCarQty=ISNULL(@SumINCount,0)
		IF ISNULL(@SumINCount,0)>=ISNULL(@CarQty,0)   
		 BEGIN
			SET @Flag=3 --移动到强制装车处
			SET @IsAutoCloseCar=1
		 END
		ELSE
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:装车成功,请继续扫描批号!' 
			RETURN 0
		 END 
	 END
	 
	IF @Flag=3  --强制装车
	 BEGIN				
		DECLARE @t TABLE
		(
			ProductId CHAR(12),
			LotSN NVARCHAR(50),
			WorkflowId CHAR(12),
			WorkflowStepId CHAR(12),
			SpecificationId CHAR(12),
			LotId CHAR(12),
			MOId CHAR(12),
			MOItemId CHAR(12),
			Qty DECIMAL(18,4),
			LatestMoveDate DATETIME,
			POItemId CHAR(12),
			RowNum INT IDENTITY(1,1)
		)
		
		INSERT INTO @t
		SELECT DISTINCT Lot.ProductId,
			   Lot.LotSN,
			   Lot.WorkflowId,
			   Lot.WorkflowStepId,
			   Lot.SpecificationId,
			   Lot.LotId,
			   Lot.MOId,
			   Lot.MOItemId,
			   Lot.Qty,
			   Lot.LatestMoveDate,
			   Lot.POItemId
		FROM dbo.Lot  WITH(NOLOCK) 
		LEFT JOIN dbo.DataChainLoadCar  WITH(NOLOCK) ON dbo.Lot.LotId = dbo.DataChainLoadCar.LotID
		WHERE DataChainLoadCar.CarSN=@CarSN
		
		SET @InCarQty=0
		SELECT @InCarQty=COUNT(1) FROM @t
		
		DECLARE @_SpecificationId1 CHAR(12)
		
		IF @InCarQty<=0
		 BEGIN
			SET @IsAutoCloseCar=0
			SET @I_ReturnMessage='ServerMessage:车号['+@CarSN+']未绑定任何条码!' 
			RETURN -1
		 END
		IF (SELECT COUNT(DISTINCT WorkflowStepId) FROM @t)>1
		 BEGIN
			SET @IsAutoCloseCar=0
			SET @I_ReturnMessage='ServerMessage:车号['+@CarSN+']中的条码状态不一致!' 
			RETURN -1
		 END
		IF ISNULL(@WorkflowStepId,'')=''
		 BEGIN
			SELECT TOP 1 @WorkflowStepId=WorkflowStepId ,
						 @WorkflowId=WorkflowId ,
						 @_SpecificationId1=SpecificationId
			FROM @t
			
			IF ISNULL(@WorkflowStepId,'')=''
			 BEGIN
				SET @IsAutoCloseCar=0
				SET @I_ReturnMessage='ServerMessage:未获取到节点!' 
				RETURN -1
			 END
			IF ISNULL(@_SpecificationId1,'')!=@_SpecificationId
			 BEGIN
				SET @IsAutoCloseCar=0
				SET @I_ReturnMessage='ServerMessage:请确认是否使用错程序!' 
				RETURN -1
			 END
		 END
		
		DECLARE @NextSpecificationId CHAR(12)
		DECLARE @NextWorkflowStepId CHAR(12)
		DECLARE @NextNextWorkflowStepId CHAR(12)
		
		SELECT @NextWorkflowStepId=ToWorkflowStepId FROM dbo.WorkflowPath  WITH(NOLOCK) WHERE WorkflowStepId=@WorkflowStepId --AND WorkflowId=@WorkflowId 
		IF @NextWorkflowStepId IS NOT NULL
		 BEGIN
			SELECT @NextSpecificationId=SpecificationId FROM dbo.WorkflowStep  WITH(NOLOCK) WHERE WorkflowStepId=@NextWorkflowStepId
			SELECT @NextNextWorkflowStepId=ToWorkflowStepId FROM dbo.WorkflowPath  WITH(NOLOCK) WHERE WorkflowStepId=@NextWorkflowStepId AND IsDefaultWorkflowPath=1
		 END
		ELSE
		 BEGIN
				SET @IsAutoCloseCar=0
				SET @I_ReturnMessage='ServerMessage:未获取到下一节点!' 
				RETURN -1
		 END
		 
		
		 
		UPDATE dbo.MOItemLot SET BrandStatus='1',Note='closed' WHERE  MOId=@MOId AND SNType='CartonSN' AND LotSN=@CarSN
		
		----声明表 ID
		DECLARE @PKDataSetDataChain1 TABLE  -- 数据链DC
		(
			RowNum INT,
			PKId CHAR(12)
		)
		
		DECLARE @PKDataSetDataChain2 TABLE  --数据链MOVE
		(
			RowNum INT,
			PKId CHAR(12)
		)
		
		DECLARE @PKDataSetDataChainMove TABLE --DataChainMove
		(
			RowNum INT,
			PKId CHAR(12)
		)
		
		DECLARE @c1 INT
		SELECT @c1=COUNT(1) FROM @t
		
		INSERT INTO @PKDataSetDataChain1(RowNum,PkID)
		EXEC SysGetBatchObjectPKId @ObjectName = N'DataChain', @RowCount = @c1
		
		INSERT INTO @PKDataSetDataChain2(RowNum,PkID)
		EXEC SysGetBatchObjectPKId @ObjectName = N'DataChain', @RowCount = @c1
		
		INSERT INTO @PKDataSetDataChainMove(RowNum,PkID)
		EXEC SysGetBatchObjectPKId @ObjectName = N'DataChainMove', @RowCount = @c1
		
		INSERT INTO DataChain (
				DataChainId,
				LotId,
				MOId,
				MOItemId,
				Qty,
				TxnCode,
				ProductId,
				UserId,
				WorkcenterId,
				ResourceId,
				ShiftId,
				SpecificationId,
				WorkflowStepId,
				PluginId,
				CreateDate
			)
		SELECT [@PKDataSetDataChain1].PKId,
			   [@t].LotId,
			   [@t].MOId,
			   [@t].MOItemId,
			   [@t].Qty,
			   'DC' AS TxnCode,
			   [@t].ProductId,
			   @I_OrBitUserId AS UserId,
			   @WorkcenterId AS WorkcenterId,
			   @I_ResourceId AS ResourceId,
			   '' AS ShiftId,
			   [@t].SpecificationId,
			   [@t].WorkflowStepId,
			   @I_PlugInCommand AS PluginId,
			   GETDATE() AS CreateDate
		FROM @t LEFT JOIN @PKDataSetDataChain1 ON [@t].RowNum=[@PKDataSetDataChain1].RowNum
		UNION ALL
		SELECT [@PKDataSetDataChain2].PKId,
			   [@t].LotId,
			   [@t].MOId,
			   [@t].MOItemId,
			   [@t].Qty,
			   'MOVE' AS TxnCode,
			   [@t].ProductId,
			   @I_OrBitUserId AS UserId,
			   @WorkcenterId AS WorkcenterId,
			   @I_ResourceId AS ResourceId,
			   '' AS ShiftId,
			   ISNULL(@NextSpecificationId,'') AS SpecificationId,
			   ISNULL(@NextWorkflowStepId,'') AS WorkflowStepId,
			   @I_PlugInCommand AS PluginId,
			   DATEADD(millisecond,100,GETDATE()) AS CreateDate --add 100 millisecond 
		FROM @t LEFT JOIN @PKDataSetDataChain2 ON [@t].RowNum=[@PKDataSetDataChain2].RowNum
		
		
		INSERT INTO DataChainMove  (
				DataChainMoveId,
				DataChainId,
				LotId,
				MOId,
				MOItemId,
				Qty,
				NonStdMoveReasonId,
				IsNonStdMove,
				WorkflowStepId,
				ToWorkflowStepId,
				ResourceId,
				ToResourceId,
				WorkflowId,
				ToWorkflowId,
				ShiftId,
				ToShiftId,
				LotInDate,
				LotOutDate,
				CycleTime1,
				CycleTime2,
				UserId
				)
		SELECT [@PKDataSetDataChainMove].PKId AS DataChainMoveId,
			   [@PKDataSetDataChain2].PKId AS DataChainId,
			   [@t].LotId,
			   [@t].MOId,
			   [@t].MOItemId,
			   [@t].Qty,
			   '' AS NonStdMoveReasonId,
			   0 AS IsNonStdMove,
			   @WorkflowStepId AS WorkflowStepId,
			   @NextWorkflowStepId AS WorkflowStepId,
			   @I_ResourceId AS ResourceId,
			   @I_ResourceId AS ToResourceId,
			   [@t].WorkflowId,
			   [@t].WorkflowId AS ToWorkflowId,
			   '' AS ShiftId,
			   '' AS ToShiftId,
			   GETDATE() AS LotInDate,
			   GETDATE() AS LotOutDate,
			   CAST(GETDATE()-[@t].LatestMoveDate AS DECIMAL(18,3)) AS CycleTime1,
			   0 AS CycleTime2,
			   @I_OrBitUserId AS UserId
		FROM @t 
		LEFT JOIN @PKDataSetDataChainMove ON [@t].RowNum=[@PKDataSetDataChainMove].RowNum
		LEFT JOIN @PKDataSetDataChain2 ON [@PKDataSetDataChainMove].RowNum = [@PKDataSetDataChain2].RowNum
		
		
		UPDATE dbo.Lot
		SET WorkFlowStepID=@NextWorkflowStepId,
			SpecificationId=@NextSpecificationId,
			WorkCenterId=@WorkCenterId,
			NextWorkFlowStepID=@NextNextWorkflowStepId,
			PreviousWorkflowStepId=@WorkflowStepId,
			LatestTxnCode='DC',						
			ResourceID=@I_ResourceId,
			LatestUserId=@I_OrBitUserId,
			ShiftID='',
			LatestMoveDate=GETDATE(),
			LatestActivityDate=GETDATE()
		WHERE EXISTS
		(
			SELECT 1 FROM @t WHERE LotId=Lot.LotId
		)
		---------过站统计 开始
		declare @DateTime datetime
		declare @ShiftId	nchar(12)
		declare @tCount		int	--装车数
		select @tCount=COUNT(*) from @t
		set @tCount =ISNULL(@tCount,0)
		
		 SET @DateTime=ISNULL(@DateTime,GETDATE())
		DECLARE @CreateDate DATE
		DECLARE @TimeSlice INT
		
		IF ISNULL(@ShiftId,'')=''
		 BEGIN
			EXEC dbo.txn_GetShiftId
				 @DateTime=@DateTime,
				 @ShiftId = @ShiftId OUTPUT -- char(12)
		 END
		
		EXEC dbo.Proc_SpecificationStatisticsTimeSlice
			@StatisticsDateTime =@DateTime, -- datetime
			@Date = @CreateDate OUTPUT, -- date
			@TimeSlice = @TimeSlice OUTPUT-- int 
		    
		SET @LotId=ISNULL(@LotId,'')
		SET @MOId=ISNULL(@MOId,'') 
		SET @WorkcenterId=ISNULL(@WorkcenterId,'')
		SET @SpecificationId= 'SPE10000004Q' --ISNULL(@_SpecificationId,'') 统计装车过站数,规程改为 正常的装车规程以方便统计
		SET @ShiftId=ISNULL(@ShiftId,'')
		SET @TimeSlice=ISNULL(@TimeSlice,-1)
		SET @CreateDate=ISNULL(@CreateDate,GETDATE())
		
		IF EXISTS(SELECT 1 FROM dbo.Base_Statistics  WITH(NOLOCK) 
			WHERE CreateDate=@CreateDate
			AND TimeSlice=@TimeSlice
			AND MOId=@MOId
			AND WorkcenterId=@WorkcenterId
			AND ShiftId=@ShiftId
			AND SpecificationId=@SpecificationId)
		 BEGIN
			UPDATE Base_Statistics SET Qty=ISNULL(Qty,0)+@tCount
			WHERE CreateDate=@CreateDate
			AND TimeSlice=@TimeSlice
			AND MOId=@MOId
			AND WorkcenterId=@WorkcenterId
			AND ShiftId=@ShiftId
			AND SpecificationId=@SpecificationId
		 END
		ELSE
		 BEGIN
			INSERT INTO dbo.Base_Statistics
					( CreateDate ,
					  TimeSlice ,
					  MOId ,
					  WorkcenterId ,
					  ShiftId ,
					  SpecificationId ,
					  Qty
					)
			VALUES  ( @CreateDate , -- CreateDate - date
					  @TimeSlice , -- TimeSlice - int
					  @MOId , -- MOId - char(12)
					  @WorkcenterId , -- WorkcenterId - char(12)
					  @ShiftId , -- ShiftId - char(12)
					  @SpecificationId , -- SpecificationId - char(12)
					  @tCount  -- Qty - bigint
					)
		 END
		 
		---------过站统计 结束
		 
	
 
		
		
		SET @IsComplete=1
		IF @IsAutoCloseCar=1
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:装车成功,车号['+@CarSN+']已自动关闭,请扫描下一车号!'
			RETURN 0  
		 END
		ELSE
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:强制装车号['+@CarSN+']成功!'
			RETURN 0  
		 END		
	 END
	 
	IF @Flag=4 --清空未关闭的车号
	 BEGIN
		DECLARE @t1 TABLE
		(
			ProductId CHAR(12),
			LotSN NVARCHAR(50),
			WorkflowId CHAR(12),
			WorkflowStepId CHAR(12),
			SpecificationId CHAR(12),
			LotId CHAR(12),
			MOId CHAR(12),
			MOItemId CHAR(12),
			Qty DECIMAL(18,4),
			LatestMoveDate DATETIME,
			POItemId CHAR(12),
			DatachainLoadCarID CHAR(12),
			RowNum INT IDENTITY(1,1)
		)
		
		INSERT INTO @t1
		SELECT DISTINCT Lot.ProductId,
			   Lot.LotSN,
			   Lot.WorkflowId,
			   Lot.WorkflowStepId,
			   Lot.SpecificationId,
			   Lot.LotId,
			   Lot.MOId,
			   Lot.MOItemId,
			   Lot.Qty,
			   Lot.LatestMoveDate,
			   Lot.POItemId,
			   DataChainLoadCar.DatachainLoadCarID
		FROM dbo.Lot  WITH(NOLOCK) 
		LEFT JOIN dbo.DataChainLoadCar  WITH(NOLOCK) ON dbo.Lot.LotId = dbo.DataChainLoadCar.LotID
		WHERE DataChainLoadCar.CarSN=@CarSN
		
		
		----批量申请并插入到临时表中
		DECLARE @c2 INT
		SELECT @c2=COUNT(1) FROM @t1
		
		----声明表 ID
		DECLARE @PKDataSetDataChain3 TABLE  -- 数据链DC
		(
			RowNum INT,
			PKId CHAR(12)
		)
		
		DECLARE @PKDataSetUserComment TABLE  --数据链备注
		(
			RowNum INT,
			PKId CHAR(12)
		)
		
		INSERT INTO @PKDataSetDataChain3(RowNum,PkID)
		EXEC SysGetBatchObjectPKId @ObjectName = N'DataChain', @RowCount = @c2
		
		INSERT INTO @PKDataSetUserComment(RowNum,PkID)
		EXEC SysGetBatchObjectPKId @ObjectName = N'DataChainUserComment', @RowCount = @c2
		
		INSERT INTO DataChain (
			DataChainId,
			LotId,
			MOId,
			MOItemId,
			Qty,
			TxnCode,
			ProductId,
			UserId,
			WorkcenterId,
			ResourceId,
			ShiftId,
			SpecificationId,
			WorkflowStepId,
			PluginId,
			CreateDate
		)
		SELECT [@PKDataSetDataChain3].PKId,
			   [@t1].LotId,
			   [@t1].MOId,
			   [@t1].MOItemId,
			   [@t1].Qty,
			   'DC' AS TxnCode,
			   [@t1].ProductId,
			   @I_OrBitUserId AS UserId,
			   @WorkcenterId AS WorkcenterId,
			   @I_ResourceId AS ResourceId,
			   '' AS ShiftId,
			   [@t1].SpecificationId,
			   [@t1].WorkflowStepId,
			   @I_PlugInCommand AS PluginId,
			   GETDATE() AS CreateDate
		FROM @t1 LEFT JOIN @PKDataSetDataChain3 ON [@t1].RowNum=[@PKDataSetDataChain3].RowNum
		
		
		--insert  move
		INSERT INTO DataChainUserComment (
					DataChainUserCommentId,
					DataChainId,
					UserComment
				)
		SELECT [@PKDataSetUserComment].PKId AS DataChainUserCommentId,
			   [@PKDataSetDataChain3].PKId AS DataChainId,
			   '清空车号['+@CarSN+']' AS UserComment
		FROM @PKDataSetUserComment 
		LEFT JOIN @PKDataSetDataChain3 ON [@PKDataSetUserComment].RowNum = [@PKDataSetDataChain3].RowNum	
		
		
		DELETE DataChainLoadCar WHERE DatachainLoadCarID IN(SELECT DatachainLoadCarID FROM @t1)
		UPDATE dbo.Lot SET ProductionLot=NULL WHERE LotId IN(SELECT LotId FROM @t1)
		
		SET @I_ReturnMessage='ServerMessage:清空车号['+@CarSN+']成功!'
		RETURN 0  
	 END
	
END