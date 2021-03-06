USE [OrBitX]
GO
/****** Object:  StoredProcedure [dbo].[Txn_SMTIssueExeNew_JM]    Script Date: 2018-5-14 8:37:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[Txn_SMTIssueExeNew_JM]
@I_Sender nvarchar(50) = '',
@I_ReturnMessage nvarchar(max)='' output,  --返回的信息,支持多语言
@I_ExceptionFieldName nvarchar(100)='' output, --向客户端报告引起冲突的字段
@I_LanguageId char(1)='1',				--客户端传入的语言ID
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)= '',			--用户ID
@I_OrBitUserName nvarchar(100)= '',	--用户名
@I_ResourceId	char(12)= '',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)= '',	--资源名
@I_PKId char(12) = '',				--主键
@I_SourcePKId char(12)='',			--执行拷贝时传入的源主键  
@I_ParentPKId char(12)='',			--父级主键
@I_Parameter nvarchar(100)='',		--插件参数	
@LotSN nvarchar(40)=''	,			--前台扫描入的主批号
@IsCheckSpecification bit='true',
@paol int   =0					,	--默认为零抛料为实际数量	如果抛料就传入就执行@paol 传入的数量执行循环扣料,如果为小板就传入小板实际数量
@xiaob INT =0						--默认为0 如果为小板这@paol<>0 @xiaob为1
AS
BEGIN

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED --20180118
	SET XACT_ABORT ON
	
	DECLARE  @temp_issueqty DECIMAL(10,4)=0
	
	set @IsCheckSpecification=ISNULL(@IsCheckSpecification,'true')
	DECLARE 
	@WaringQty INT=10,--报警数量
	@LotId CHAR(12),
	@ABSide NVARCHAR(20),
	@MOId CHAR(12),
	@MOName NVARCHAR(50),
	@SpecificationId CHAR(12),
	@SpecificationName NVARCHAR(50),
	@WorkflowStepId CHAR(12),
	@ProductionLot VARCHAR(50),
	@PCBType NVARCHAR(20),
	@WorkflowID CHAR(12),
	@MOSMTPath NVARCHAR(10),
	@_SpecificationId1 CHAR(12)='SPE10000004N',--贴片所对应的规程
	@_SpecificationId2 CHAR(12)='SPE1000000DN',--贴片所对应的规程
	@IsSMTMountRequired BIT,
	@IsSMTMountItemAll BIT,
	
	@WorkcenterId CHAR(12),
	@WorkcenterName NVARCHAR(50),
	@IsLock BIT,
	@DeviceTypeId CHAR(12),
	@DeviceTypeName NVARCHAR(50),
	@IsJITMode BIT    --Jason.Wang 2015-04-08

	
	
	
	DECLARE @LinkLotSN TABLE
	(
		LotId CHAR(12),
		LotSN NVARCHAR(50),
		ProductId CHAR(12),
		Qty DECIMAL(18,4),
		ABSide NVARCHAR(20),
		SpecificationId CHAR(12),
		IsLock BIT,
		MOId CHAR(12),
		MOItemId CHAR(12),
		WorkflowId CHAR(12),
		LatestMoveDate DATETIME, 
		WorkflowStepId CHAR(12),
		RowNum INT,
		MakeUpCount INT,
		ProductionLot NVARCHAR(50)
	)
	 
	
	DECLARE @StationNo NVARCHAR(50)
	DECLARE @SLotNO NVARCHAR(50)
	DECLARE @SMTProductId CHAR(12)
	DECLARE @SMTProductName NVARCHAR(400)
	DECLARE @IsMust BIT
	DECLARE @BaseQty DECIMAL(18,4)
	DECLARE @sumQty DECIMAL(18,4)
	DECLARE @LotSNCount INT
	DECLARE @CustomerId CHAR(12)
	DECLARE @WOSN NVARCHAR(50)
	DECLARE @IsHuaWeiCustomer BIT
	DECLARE @ToWorkflowStepId CHAR(12)
	DECLARE @ToSpeicifcationId CHAR(12)
	DECLARE @ToNextWorkflowStepId CHAR(12)
	DECLARE @Isbug BIT=1
	DECLARE @ResultTime DATETIME=GETDATE()
	DECLARE @_SMTMount TABLE   --定义料站表
	(
		ProductId CHAR(12),
		ProductName NVARCHAR(400),
		SLotNO NVARCHAR(20),
		StationNo NVARCHAR(20),
		BaseQty DECIMAL(18,4),
		IsMust BIT,
		RowNum INT
	)
	
	DECLARE @_StationNoSlot TABLE   --定义机台-槽位 --用来循环扣料
	(
		StationNo NVARCHAR(20),
		SLotNO NVARCHAR(20),
		BaseQty DECIMAL(18,4),
		RowNum INT
	)
	
	DECLARE @_SMTMountLot TABLE --定义上料表
	(
		LotOnSMTId CHAR(12),
		LotId CHAR(12),
		LotSN NVARCHAR(50),
		ProductId CHAR(12),
		Qty DECIMAL(18,4),
		StationNO NVARCHAR(20),
		SLotNO NVARCHAR(20),
		IsLock BIT,
		CreateDate DATETIME,
		RowNum INT
	)
	
	DECLARE @i INT
	DECLARE @s INT
	
	
	BEGIN  --资源校验
		SET @I_ResourceId=NULL
		SELECT @I_ResourceId=ResourceId ,
			   @WorkcenterId=dbo.Resource.WorkcenterId,
			   @WorkcenterName=ISNULL(dbo.Workcenter.WorkcenterName,'N/A'),
			   @DeviceTypeId=dbo.Resource.DeviceTypeId,
			   @DeviceTypeName=ISNULL(dbo.DeviceType.DeviceTypeName,'N/A')
		FROM Resource WITH(NOLOCK)
		LEFT JOIN dbo.Workcenter WITH(NOLOCK) ON dbo.Resource.WorkcenterId = dbo.Workcenter.WorkcenterId
		LEFT JOIN dbo.DeviceType WITH(NOLOCK) ON dbo.Resource.DeviceTypeId=dbo.DeviceType.DeviceTypeId
		WHERE ResourceName=ISNULL(@I_ResourceName,'')
		
		--by luoll 20150325 SMT 上料表LotOnSMT 中的线体用的是工作中心的简称
		DECLARE @ShortName NVARCHAR(10)
		SELECT @ShortName=ShortName FROM  dbo.WorkCenter WITH(NOLOCK) WHERE WorkcenterName=@WorkcenterName

		IF @I_ResourceId IS NULL
		 BEGIN
			SET  @I_ReturnMessage='ServerMessage: 本地资源名称【'+ISNULL(@I_ResourceName,'N/A')+'】没有在MES系统中注册!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		 END
		IF ISNULL(@WorkcenterId,'')=''
		 BEGIN
			SET  @I_ReturnMessage='ServerMessage: 本地资源【'+ISNULL(@I_ResourceName,'N/A')+'】在系统中没有指定工作中心!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		 END
		IF ISNULL(@DeviceTypeId,'')=''
		 BEGIN
			SET  @I_ReturnMessage='ServerMessage: 本地资源【'+ISNULL(@I_ResourceName,'N/A')+'】在系统中没有指定设备分类!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		 END
	END
	
	DECLARE @IntervalotId CHAR(12)
	BEGIN  --批号校验
	    SELECT @LotId=LotId FROM dbo.Lot WITH(NOLOCK) WHERE LotSN=ISNULL(@LotSN,'N/A')

		SELECT @MOId=MO.MOID,
			   @MOName=ISNULL(MO.MOName,'N/A'),
			   @SpecificationId=Lot.SpecificationId,
			   @WorkflowStepId =Lot.WorkflowStepId,
			   @ProductionLot= ISNULL(Lot.ProductionLot,''),
			   @PCBType =MO.PCBType ,
			   @MOSMTPath=MO.MOSMTPath,
			   @WorkflowID=MO.WorkflowId,
			   @SpecificationName=SpecificationRoot.SpecificationName,
			   @ABSide=Lot.ABSide,
			   @IsSMTMountRequired=ISNULL(dbo.Product.IsSMTMountRequired,'false'),
			   @IsSMTMountItemAll=ISNULL(dbo.Product.IsSMTMountItemAll,'false'),
			   @IsLock=ISNULL(Lot.IsLock,'false'),
			   @CustomerId=MO.CustomerId,
			   @WOSN=MO.WOSN,
			   @IsJITMode=IsJITMode
		FROM  dbo.Lot WITH(NOLOCK)
		LEFT JOIN MO WITH(NOLOCK) ON Lot.MOId =MO.MOID
		LEFT JOIN dbo.Product WITH(NOLOCK) ON dbo.MO.ProductId = dbo.Product.ProductId
		LEFT JOIN dbo.Specification WITH(NOLOCK) ON Lot.SpecificationId=dbo.Specification.SpecificationId
		LEFT JOIN dbo.SpecificationRoot WITH(NOLOCK) ON dbo.Specification.SpecificationRootId = dbo.SpecificationRoot.SpecificationRootId
		WHERE Lot.LotId=@LotId
IF @MOId IN ('MOD100004SPT','MOD100004SWF')
BEGIN
   IF @Isbug=1
   BEGIN
      INSERT INTO dbo.CatchErooeLog
              ( ProcName ,ErooeCommad , CreateDate ,Duration)
      VALUES  ( N'Txn_SMTIssueExeNew_JM' , -- ProcName - nvarchar(50)
                N'1' , -- ErooeCommad - nvarchar(500)
                GETDATE() , -- CreateDate - datetime
                DATEDIFF(MILLISECOND,@ResultTime,GETDATE()) 
              )
	  SET @ResultTime=GETDATE()
   END
END	
				------------------------------------------钢网时间管控 add by haomj 20150618-------------------------------------------------------

		
		--DECLARE @WashOnLine DATETIME
		--DECLARE @WashOutLine DATETIME
		--DECLARE @InStockDate DATETIME
		--DECLARE @OutStockDate DATETIME

		--SELECT TOP 1 @WashOnLine=washOnline,@WashOutLine=washoutline,@InStockDate=instockdate,@OutStockDate=outstockdate 
		--FROM dbo.SteelMeshInfo WHERE moid=@moid AND workcenter=@WorkcenterName ORDER BY OutStockDate DESC

		--IF @WashOnLine<@WashOutLine AND @WashOnLine<@OutStockDate
		--BEGIN
		--	IF DATEPART(MINUTE,(GETDATE()-@OutStockDate))>'60'
		--	BEGIN 
		--		SET @I_ReturnMessage='ServerMessage: 扣料失败--该线体上钢网已使用超过一小时，请在线清洗。'
		--		RETURN -1
		--	END
		--END

		--ELSE IF @WashOnLine>@OutStockDate AND @WashOutLine<@OutStockDate
		--BEGIN 
		--	IF DATEPART(MINUTE,(GETDATE()-@WashOnLine))>'60'
		--	BEGIN 
		--		SET @I_ReturnMessage='ServerMessage: 扣料失败--该线体上钢网已使用超过一小时，请在线清洗。'
		--		RETURN -1
		--	END 

		--	IF DATEPART(HOUR ,(GETDATE()-@OutStockDate))>'12'
		--	BEGIN 
		--		SET @I_ReturnMessage='ServerMessage: 扣料失败--该线体上的钢网距上次离线清洗已超过12小时，请离线清洗。'
		--	END 
		--END

		--ELSE IF @WashOnLine>@OutStockDate AND @WashOutLine<@OutStockDate 
		--BEGIN
		--	IF DATEPART(MINUTE,(GETDATE()-@WashOnLine))>'60'
		--	BEGIN 
		--		SET @I_ReturnMessage='ServerMessage: 扣料失败--该线体上钢网已使用超过一小时，请在线清洗。'
		--		RETURN -1
		--	END 

		--	IF DATEPART(HOUR ,(GETDATE()-@WashOutLine))>'12'
		--	BEGIN 
		--		SET @I_ReturnMessage='ServerMessage: 扣料失败--该线体上的钢网距上次离线清洗已超过12小时，请离线清洗。'
		--	END  
		--END

		--------------------------------------------



		

	   SET @IntervalotId=@LotId
	   IF @LotId IS NULL 
		BEGIN
			SET @I_ReturnMessage='ServerMessage: 批号【'+ISNULL(@LotSN,'N/A')+'】1不存在,请检查!'
			SET @I_ExceptionFieldName='LotSN'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		END
	   IF @IsLock='true'
		BEGIN
			SET @I_ReturnMessage='ServerMessage: 批号【'+ISNULL(@LotSN,'N/A')+'】已被锁定,请检查!'
			SET @I_ExceptionFieldName='LotSN'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		END
		
	   IF @ProductionLot=''
	    BEGIN
			SET @I_ReturnMessage='ServerMessage: 批号【'+ISNULL(@LotSN,'N/A')+'】的连板号为空,请检查!'
			SET @I_ExceptionFieldName='LotSN'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	    END
		
	   IF ISNULL(@MOId,'')=''
	    BEGIN
			SET @I_ReturnMessage='ServerMessage: 批号【'+ISNULL(@LotSN,'N/A')+'】没有找到对应的工单信息!'
			SET @I_ExceptionFieldName='LotSN'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	    END
	   IF ISNULL(@WorkflowID,'')=''
	    BEGIN
			SET @I_ReturnMessage='ServerMessage: 工单【'+@MOName+'】没有找到对应的工作流信息!'
			SET @I_ExceptionFieldName='LotSN'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	    END
	   IF ISNULL(@SpecificationId,'')='' OR ISNULL(@WorkflowStepId,'')=''
	    BEGIN
			SET @I_ReturnMessage='ServerMessage: 批号【'+ISNULL(@LotSN,'N/A')+'】没有找到对应的当前规程(节点)信息!'
			SET @I_ExceptionFieldName='LotSN'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	    END
	   IF @IsCheckSpecification='true' and (@SpecificationId <> @_SpecificationId1 AND @SpecificationId <> @_SpecificationId2)
		BEGIN
			SET @I_ReturnMessage='ServerMessage: 批号【'+ISNULL(@LotSN,'N/A')+'】目前所在站点为【'+ISNULL(@SpecificationName,'N/A')+'】,本站点无法操作!'
			SET @I_ExceptionFieldName='LotSN'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		END
		
	
	   
	   SELECT @ToWorkflowStepId=ToWorkflowStepId FROM dbo.WorkflowPath  WITH(NOLOCK) WHERE WorkflowStepId=@WorkflowStepId AND IsDefaultWorkflowPath=1
	   IF @ToWorkflowStepId IS NULL
	    BEGIN
			SET @I_ReturnMessage='ServerMessage: 站点【'+ISNULL(@SpecificationName,'N/A')+'】未找到下一节点!'
			SET @I_ExceptionFieldName='LotSN'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	    END
	   ELSE
	    BEGIN
			SELECT @ToSpeicifcationId=SpecificationId FROM dbo.WorkflowStep  WITH(NOLOCK) WHERE WorkflowStepId=@ToWorkflowStepId
			SELECT @ToNextWorkflowStepId=ToWorkflowStepId FROM dbo.WorkflowPath  WITH(NOLOCK) WHERE WorkflowStepId=@ToWorkflowStepId AND IsDefaultWorkflowPath=1
	    END
	   
   END
     
    --add 华为任务令校验
    BEGIN
		EXEC dbo.txn_IsHuaWeiCustomer @CustomerId = @CustomerId, -- char(12)
									  @MOID=@MOId,
									  @IsHuaWeiCustomer = @IsHuaWeiCustomer OUTPUT -- bit
		--IF ISNULL(@IsHuaWeiCustomer,'false')='true' AND ISNULL(@WOSN,'')=''
		-- BEGIN
		--	SET @I_ReturnMessage= 'ServerMessage:批号【'+ISNULL(@LotSN,'N/A')+'】对应的工单【'+@MOName+'】是华为工单,请先维护华为工单的任务令(工单信息->标签任务号)!'
		--	SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
		--	RETURN -1
		-- END
    END 
    
    BEGIN  --得到连板批号
		INSERT INTO @LinkLotSN
		SELECT LotId,LotSN,ProductId,Qty,ABSide,SpecificationId,ISNULL(IsLock,'false') AS IsLock,
			   MOId,MOItemId,WorkflowId,LatestMoveDate,WorkflowStepId,
			   ROW_NUMBER()OVER(ORDER BY ISNULL('',''))AS RowNum,MakeUpCount,ProductionLot
		FROM dbo.Lot WITH(NOLOCK) WHERE LotId IN (SELECT LotId FROM dbo.Lot WITH(NOLOCK) WHERE MOId=@MOId AND ProductionLot=@ProductionLot)
		--WHERE MOId=@MOId AND ISNULL(ProductionLot,'')=@ProductionLot   --20161010 xiezq 更改为按LOTID获取
		
		IF(SELECT COUNT(1) FROM (
							       SELECT SpecificationId FROM @LinkLotSN GROUP BY SpecificationId
								)A)>1
		 BEGIN
			SET @I_ReturnMessage='ServerMessage: 系统错误,连板【'+@ProductionLot+'】的批号不在同一规程,请联系MES管理处!'
			SET @I_ExceptionFieldName='LotSN'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		 END
		 
		IF(SELECT COUNT(1) FROM (
							       SELECT ABSide FROM @LinkLotSN GROUP BY ABSide
								)A)>1
		 BEGIN
			SET @I_ReturnMessage='ServerMessage: 系统错误,连板【'+@ProductionLot+'】的批号的A/B面板不一致,系统无法识别,请联系MES管理处!'
			SET @I_ExceptionFieldName='LotSN'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		 END
		 
	   SELECT @ABSide=MIN(ABSide),@LotSNCount=COUNT(1) FROM @LinkLotSN
	   IF @paol<>0
	   BEGIN
			IF	@xiaob<>0
			BEGIN
			   --SET @LotSNCount=@paol; --非抛料 连板数
				SET @LotSNCount=@xiaob;
			END
			ELSE
			begin
				SET @LotSNCount=@paol
				--SET @LotSNCount=@xiaob;
			END
		
	   END		
	   IF ISNULL(@ABSide,'')=''
	    BEGIN
			SET @I_ReturnMessage='ServerMessage: 系统错误,连板【'+@ProductionLot+'】的批号的A/B面板为空,系统无法识别,请联系MES管理处!'
			SET @I_ExceptionFieldName='LotSN'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	    END


		--------------------------------------------
		--判断独立模式：尽早判断卡出贴片程序
		DECLARE  @t_side  TABLE(
		  num INT  IDENTITY(1,1),
		  side NVARCHAR(5)
		)
		INSERT  INTO  @t_side
		        (side )
		SELECT  ABSide FROM  dbo.MO_SMTMount  WITH(NOLOCK)
		 INNER  JOIN  dbo.SMTMount  WITH(NOLOCK) ON dbo.MO_SMTMount.SMTMountName = dbo.SMTMount.SMTMountName
		INNER  JOIN  dbo.SMTMountItem  WITH(NOLOCK) ON  dbo.SMTMount.SMTMountId=dbo.SMTMountItem.SMTMountId
		WHERE  dbo.MO_SMTMount.MOId=@MOId AND  dbo.SMTMount.Side=@ABSide  AND dbo.SMTMount.DeviceTypeId=@DeviceTypeId
		
		IF  EXISTS(SELECT  1  FROM    @t_side   WHERE CHARINDEX('A',side,0)!=0 OR CHARINDEX('B',side,0)!=0)
		BEGIN
		         SET @I_ReturnMessage='ServerMessage: 该工单对应的料站表存在A或B面,贴片程序应该选择独立模式贴片!'
				 SET @I_ExceptionFieldName='LotSN'
			
				SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
				RETURN -1
		    
		END
		------------------------------------------

	   IF EXISTS(SELECT 1 FROM @LinkLotSN WHERE IsLock='true' )
	    BEGIN
			SET @I_ReturnMessage='ServerMessage: 系统错误,连板【'+@ProductionLot+'】已被锁定,请检查!'
			SET @I_ExceptionFieldName='LotSN'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	    END
    END 
    

	----------------OSP检测 暂时屏蔽，待培训后开启，邓峰--------------------------------
	--SPE10000004N  SPE1000000DN

	IF  @IsHuaWeiCustomer='true'  
	BEGIN
	  IF  @SpecificationId='SPE10000004N'
	  BEGIN
			IF  DATEDIFF(HOUR,(SELECT  top 1 CreateDate  FROM  dbo.DataChain WITH(NOLOCK) WHERE  LotId=@lotid  AND SpecificationId='SPE10000004L'),GETDATE())>=12
			BEGIN
				IF NOT EXISTS( SELECT 1 FROM  dbo.SMT_BAKEHOUSE_OUT WITH(NOLOCK) WHERE LotId=@lotid  AND SpecificationId='SPE10000004N')
				BEGIN
					IF @moname NOT IN ('MO060217101311','MO060218012232','MO060218012424','MO060218012426','MO060218012644','MO060218012646','MO060218012649','MO060218020120','MO060218020250','Mo060218040404')  --添加后面三个工单 郑异20180131
					BEGIN
						SET @I_ReturnMessage='ServerMessage:该连板已拆包上线超过12小时，必须进入烘烤作业'
						SET @I_ExceptionFieldName='LotSN'
						RETURN -1
					END
				END
					
			END
	  END
	 IF  @SpecificationId='SPE1000000DN'
	 BEGIN
	 IF  DATEDIFF(HOUR,(SELECT TOP 1 CreateDate  FROM  dbo.DataChain WITH(NOLOCK) WHERE  LotId=@lotid  AND SpecificationId='SPE10000004N' ORDER  BY  CreateDate  DESC ),GETDATE())>=24
			BEGIN
			IF NOT EXISTS( SELECT 1 FROM  dbo.SMT_BAKEHOUSE_OUT WITH(NOLOCK) WHERE LotId=@lotid  AND SpecificationId='SPE1000000DN' )
				BEGIN
				IF NOT EXISTS(SELECT 1 FROM dbo.ProductConfig WHERE ProductId=@moid AND ItemName='不管控回流焊超时')--20171124 增加不管控
					BEGIN
					SET @I_ReturnMessage='ServerMessage:该连板已经距离第一次回流焊超过24小时了，必须进入烘烤作业！'
					SET @I_ExceptionFieldName='LotSN'
					RETURN -1
				END
				END
			END
	 END
	END
	-----------------OSP检测--------------------------------

    
    ---钢网管控 
    BEGIN
       IF  @ShortName in ('S01','S02','S03','S04','S05','S06','S07','S08','S09','S10','S11','S12','S13','S14','S15','S16','S17','S18','S19','S20','S21','S22','S23','S24','S25','S26','S27','S28','S34','S35','S36','S37','S38','S39','S40')
       BEGIN
           DECLARE @res INT 
		   EXEC @res=[Txn_Steelmesh_issue_4d]
		   @I_ReturnMessage=@I_ReturnMessage  OUTPUT ,
		   @MOId=@MOId ,  
		   @WorkcenterName=@WorkcenterName,
		   @ABSide=@ABSide          
		   IF  @res<>0
		   BEGIN
				SET @I_ReturnMessage=isnull(@I_ReturnMessage,'')
				SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
				RETURN -1
		   END 
       END
    END

	--刮刀管控
	IF  @ShortName in ('S01','S02')
    BEGIN
        DECLARE @res3 INT 
		DECLARE @massage NVARCHAR(300)=''
		EXEC @res3=[10.2.0.25].OrBitXE.dbo.Txn_SteelmeshGD_issue_4d   --('S01','S02','S03','S04','S05','S06','S07','S08','S09','S10')
		@I_ReturnMessage=@massage  OUTPUT ,
		@MOId=@MOId ,  
		@WorkcenterName=@WorkcenterName
		   
		IF  @res3<>0
		BEGIN
			SET @I_ReturnMessage=isnull(@massage,'')
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		END 
    END
 	----25库刮刀、钢网扣数 xiezq 20170531
    IF  @ShortName  IN ('S01','S02','S03','S04','S05','S06','S07','S08','S09','S10','S11','S12','S13','S14','S15','S16','S17','S18','S19','S20','S21','S22','S23','S24','S25','S26','S27','S28','S34','S35','S36','S37','S38','S39','S40')
    BEGIN
		DECLARE @res1 INT 
		DECLARE @TReturnMessage NVARCHAR(500)
		EXEC @res1=[10.2.0.25].OrBitXE.dbo.Txn_LotOnSMTDevicePartsForLot_Domethod 
		@I_ReturnMessage=@TReturnMessage  OUTPUT ,
		@MOId=@MOId ,  
		@WorkcenterName=@WorkcenterName,
		@ABSide=@ABSide 
		            
		IF  @res1<>0
		BEGIN
			SET @I_ReturnMessage=isnull(@TReturnMessage,'')
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		END 
    END
    
  
    
    IF @IsSMTMountRequired='true'
     BEGIN  --获取料站表
        DECLARE  @smtmountid_4d  CHAR(12)
       SELECT  @smtmountid_4d=mo_smtmounttemp4d.smtmountid  FROM  dbo.mo_smtmounttemp4d WITH(NOLOCK) INNER JOIN dbo.MO WITH(NOLOCK) ON MO.MOName = mo_smtmounttemp4d.moname
       INNER  JOIN  dbo.SMTMount  WITH(NOLOCK) ON SMTMount.SMTMountId = mo_smtmounttemp4d.smtmountid 
       WHERE MOId=@MOId AND mo_smtmounttemp4d.WorkCenterID=@WorkcenterId AND Side=@ABSide
       IF ISNULL(@smtmountid_4d,'')<>''
       BEGIN
           INSERT INTO @_SMTMount
		   SELECT  SMTMountItem_temp4d.ProductId,
				   (dbo.ProductRoot.ProductName+(CASE WHEN ISNULL(Product.ProductDescription,'')='' THEN '' ELSE '/'+Product.ProductDescription END)) AS ProductName,
				   SMTMountItem_temp4d.SLotNO,             
				   @WorkcenterName+SMTMountItem_temp4d.StationNo AS StationNo,
				   SMTMountItem_temp4d.BaseQty AS BaseQty,
				   SMTMountItem_temp4d.IsMust  AS IsMust,  --ISNULL(SMTMountItem.IsMust,'false') AS IsMust, --- Modified by Qianxm on 2014.10.09 for 华技客户限制强制上料
				   ROW_NUMBER()OVER(ORDER BY ISNULL('','')) AS RowNum
				   FROM  dbo.SMTMountItem_temp4d  WITH(NOLOCK)
				   LEFT JOIN dbo.Product WITH(NOLOCK) ON dbo.SMTMountItem_temp4d.ProductId = dbo.Product.ProductId
		           LEFT JOIN dbo.ProductRoot WITH(NOLOCK) ON dbo.Product.ProductRootId = dbo.ProductRoot.ProductRootId
				   WHERE MOId=@MOId AND WorkcenterId=@WorkcenterId AND SMTMountId=@smtmountid_4d  
			IF NOT EXISTS(SELECT 1 FROM @_SMTMount)
			BEGIN
				SET @I_ReturnMessage='ServerMessage:工单该线该面有维护临时料站表，但临时料站表明细为空，请展开明细！'
				SET @I_ExceptionFieldName='LotSN'
				SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
				RETURN -1
			END   
			
		   INSERT INTO @_StationNoSlot       
		   SELECT StationNo,
				  SLotNO,
				  MAX(BaseQty),
				  ROW_NUMBER()OVER(ORDER BY ISNULL('','')) AS RowNum
		   FROM @_SMTMount
		   GROUP BY StationNo,SLotNO,BaseQty
		   
		  -- SELECT  *  FROM  @_StationNoSlot
       
       END
       ELSE
       BEGIN
     
     
       INSERT INTO @_SMTMount
       SELECT  SMTMountItem.ProductId,
               (dbo.ProductRoot.ProductName+(CASE WHEN ISNULL(Product.ProductDescription,'')='' THEN '' ELSE '/'+Product.ProductDescription END)) AS ProductName,
               SMTMountItem.SLotNO,
			   @ShortName+SMTMountItem.StationNo AS StationNo, --by luoll 20150325
			   MAX(SMTMountItem.BaseQty) AS BaseQty,
			  (CASE WHEN  @IsHuaWeiCustomer=1 THEN 1 ELSE SMTMountItem.IsMust END) AS IsMust,
               ROW_NUMBER()OVER(ORDER BY ISNULL('','')) AS RowNum
       FROM dbo.MO_SMTMount WITH(NOLOCK)
       LEFT JOIN dbo.SMTMount WITH(NOLOCK) ON dbo.MO_SMTMount.SMTMountName = dbo.SMTMount.SMTMountName
       LEFT JOIN dbo.SMTMountItem WITH(NOLOCK) ON dbo.SMTMount.SMTMountId = dbo.SMTMountItem.SMTMountId
       LEFT JOIN dbo.Product WITH(NOLOCK) ON dbo.SMTMountItem.ProductId = dbo.Product.ProductId
       LEFT JOIN dbo.ProductRoot WITH(NOLOCK) ON dbo.Product.ProductRootId = dbo.ProductRoot.ProductRootId
	   WHERE dbo.MO_SMTMount.MOId=@MOId AND dbo.SMTMount.DeviceTypeId=@DeviceTypeId AND SMTMount.Side=@ABSide
	   AND BaseQty>0
	   GROUP BY SMTMountItem.ProductId,
                dbo.ProductRoot.ProductName,
                Product.ProductDescription,
                SMTMountItem.SLotNO,
			    SMTMountItem.StationNo,
			    SMTMountItem.IsMust
	   IF @CustomerId<>'CUS1000000X3'
	   BEGIN
		   IF NOT EXISTS(SELECT 1 FROM @_SMTMount)
			BEGIN
				SET @I_ReturnMessage='ServerMessage: 工单【'+@MOName+'】在设备分类【'+@DeviceTypeName+'】中没有导入料站表('+@ABSide+'面)1!'
				SET @I_ExceptionFieldName='LotSN'
				SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
				RETURN -1
			END
	    END


		----------------------------------------------按多槽位并物料扣料模式---------------------------------------------------
		IF EXISTS(SELECT 1 FROM dbo.ProductConfig WHERE ProductId=@moid AND ItemName='是否合并站位'
		AND ItemValue='1')
		BEGIN
			-- 计算分组替代料 获取此次需要循环的真实站位表-------
			---获取有替代料关系的槽位
			SELECT * INTO  #t_common FROM  @_SMTMount t
			WHERE  EXISTS(
			SELECT  NULL  FROM   (
					SELECT  StationNo,SLotNO  FROM  @_SMTMount GROUP BY StationNo,SLotNO
					HAVING  COUNT(1)>1) a WHERE  a.StationNo=t.StationNo AND  a.SLotNO=t.SLotNO
			)
			-- SELECT  *  FROM  #t_common

			--获取每个共用料槽位最近上料信息
			SELECT  * into  #t_actual  FROM  (
			SELECT  ROW_NUMBER() OVER(PARTITION BY StationNO,SlotNO ORDER BY LotOnSMTHistoryId desc) AS if_seq, dbo.LotOnSMTHistory.lotid,ProductId,SMTLineNo,StationNO,SlotNO
			FROM  dbo.LotOnSMTHistory  WITH(NOLOCK)
			INNER JOIN lot  WITH(NOLOCK)  ON Lot.LotId = LotOnSMTHistory.LotId
			WHERE dbo.LotOnSMTHistory.moid=@moid  AND  SMTLineNo=@ShortName
			AND   SlotNO IN (SELECT  DISTINCT SLotNO FROM #t_common)
			) c
			WHERE if_seq=1
			--SELECT  *  FROM  #t_actual

			IF  (SELECT  COUNT(1) FROM  #t_actual)<>(SELECT  count(DISTINCT SLotNO)  FROM  #t_common)
			BEGIN
				SET @I_ReturnMessage='ServerMessage: 主替代料槽位没有上料记录请检查!'
				SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
				RETURN -1
			END

			DELETE  FROM  @_SMTMount  WHERE  RowNum IN (
			SELECT  RowNum  FROM  @_SMTMount  smtmount
			WHERE  EXISTS(
			SELECT  NULL FROM  #t_actual WHERE smtmount.StationNo=#t_actual.StationNO AND smtmount.SLotNO=#t_actual.SlotNO
			AND smtmount.ProductId<>#t_actual.ProductId
			)
			)
			DROP  TABLE  #t_common,#t_actual
			--SELECT   *  FROM  @_SMTMount
			
			INSERT INTO @_StationNoSlot
			SELECT  MIN(StationNo) StationNo,MIN(SLotNO) SLotNO,SUM(BaseQty)  BaseQty,
			ROW_NUMBER()OVER(ORDER BY ISNULL('',''))
			FROM  @_SMTMount
			GROUP BY ProductId
			ORDER BY StationNo,SLotNO

			--SELECT  *  FROM  @_StationNoSlot
			-- 计算分组替代料 获取此次需要循环的真实站位表----------------------------------------------------------------------
		END	
		ELSE
		BEGIN
			INSERT INTO @_StationNoSlot
			SELECT StationNo,
					SLotNO,
					BaseQty,
					ROW_NUMBER()OVER(ORDER BY ISNULL('','')) AS RowNum
			FROM @_SMTMount
			GROUP BY StationNo,SLotNO,BaseQty
		END
		----------------------------------------------按多槽位并物料扣料模式---------------------------------------------------		   
	   END
     END


	 	--SMT 飞达检测---------------20171023 dengfeng
	--IF  @ShortName in ('S01','S02')
	--BEGIN
	--		DECLARE  @fdcheck_tb  slot_table
	--		INSERT  INTO @fdcheck_tb
	--		SELECT  *  FROM  @_StationNoSlot
	--		DECLARE @res_fdcheck INT
	--		EXEC @res_fdcheck= [Txn_smt_fdcheck_4d]
	--		@I_ReturnMessage=@I_ReturnMessage  OUTPUT ,
	--		@Slot_table=@fdcheck_tb
	--		IF  @res_fdcheck<>0
	--		BEGIN
	--				SET @I_ReturnMessage=isnull(@I_ReturnMessage,'')
	--				SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
	--				RETURN -1
	--		END
	--END	
	--SMT 飞达检测---------------

      
    IF @IsSMTMountRequired='true'
     BEGIN  --获取上料表
		--add by luoll 20150325 SMT上料表LotOnSMT中的线体是工作中心的简称
		--DECLARE @ShortName NVARCHAR(10)
		--SELECT @ShortName=ShortName FROM  dbo.WorkCenter WITH(NOLOCK) WHERE WorkcenterName=@WorkcenterName
		
		INSERT INTO @_SMTMountLot
		SELECT dbo.LotOnSMT.LotOnSMTId,
			   dbo.LotOnSMT.LotId,
			   Lot.LotSN,
			   lot.ProductId,
			   Lot.Qty,
			   dbo.LotOnSMT.StationNO,
			   dbo.LotOnSMT.SLotNO,
			   ISNULL(IsLock,'false') AS IsLock,
			   LotOnSMT.CreateDate ,
			   ROW_NUMBER()OVER(ORDER BY LotOnSMT.CreateDate ASC) AS RowNum
		FROM dbo.LotOnSMT WITH(NOLOCK)
		LEFT JOIN dbo.Lot WITH(NOLOCK) ON dbo.LotOnSMT.LotId = dbo.Lot.LotId
		WHERE LotOnSMT.MOId=@MOId AND dbo.LotOnSMT.SMTLineNO=@ShortName
		AND Qty>0
		ORDER BY LotOnSMT.CreateDate ASC
				
	
		
		IF @IsSMTMountItemAll='true'  AND NOT EXISTS(SELECT 1 FROM @_SMTMountLot)
	     BEGIN
			SET @I_ReturnMessage='ServerMessage: 工单【'+@MOName+'】在线别【'+@ShortName+'】中没有上料!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	     END	
	    
	    DECLARE @_LotSNTmp NVARCHAR(50)
	    SELECT TOP 1 @_LotSNTmp=LotSN FROM @_SMTMountLot WHERE IsLock='true' AND Qty>0
	    IF @_LotSNTmp IS NOT NULL
	     BEGIN
			SET @I_ReturnMessage='ServerMessage: 物料批号【'+@_LotSNTmp+'】已被锁定,请检查!'
			SET @I_ExceptionFieldName='LotSN'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	     END

		 --------------------------------------------------------------上料解析---------------------------------------------
		IF EXISTS(SELECT 1 FROM dbo.ProductConfig WHERE ProductId=@moid AND ItemName='是否合并站位'
		AND ItemValue='1')
		BEGIN
				DECLARE  @t_lotonsmt  TABLE(
				num INT  IDENTITY(1,1),
				min_slotno NVARCHAR(50),
				slotno NVARCHAR(50)
				)
				DECLARE  @productid_minslotno TABLE(
				productid CHAR(12),
				min_slotno NVARCHAR(50)
				)
				INSERT  INTO @productid_minslotno
				SELECT   ProductId,MIN(SLotNO) FROM  @_SMTMount
				GROUP BY ProductId
				HAVING  COUNT(1)>1
		
				INSERT  INTO  @t_lotonsmt
						(  min_slotno, slotno )				
				SELECT  min_slotno,SLotNO  FROM  @_SMTMount b
				INNER JOIN  @productid_minslotno a ON b.ProductId=a.productid
				WHERE b.ProductId  IN (SELECT  productid FROM  @productid_minslotno)

				--SELECT  * FROM  @t_lotonsmt


				DECLARE  @iii INT
				DECLARE  @yyy  INT
				DECLARE  @yuan_slot NVARCHAR(50)
				DECLARE  @replace_slot NVARCHAR(50)
				SELECT  @iii=1,@yyy=COUNT(1) FROM  @t_lotonsmt
				WHILE @iii<=@yyy
				BEGIN
					SELECT  @yuan_slot=slotno,@replace_slot=min_slotno  FROM  @t_lotonsmt WHERE  num=@iii
					IF  @yuan_slot=@replace_slot
					BEGIN
						SET @iii=@iii+1
						CONTINUE
					END
					UPDATE  @_SMTMountLot  SET  SLotNO=@replace_slot WHERE  SLotNO=@yuan_slot
					SET @iii=@iii+1
				END
		END
		
		--------------------------------------------------------------上料解析---------------------------------------------

	    
     END
    
    IF @IsSMTMountRequired='true'
     BEGIN  --检查料是否有上齐以及是否够料
		IF @IsSMTMountItemAll='true'
		 BEGIN
			SET @StationNo=NULL
			SET @SLotNO=NULL
			SET @BaseQty=NULL
			SET @sumQty=NULL
			
			SELECT @StationNo=A.StationNo,@SLotNO=A.SLotNO,@BaseQty=A.BaseQty,@sumQty=SUM(ISNULL(B.Qty,0))
			FROM @_StationNoSlot A
			LEFT JOIN @_SMTMountLot B ON A.StationNo=B.StationNo AND A.SLotNO=B.SLotNO
			WHERE EXISTS
			(
				SELECT 1 FROM @_SMTMount WHERE StationNo=A.StationNo AND SLotNO=A.SLotNO AND IsMust='true'
			)
			GROUP BY A.StationNo,A.SLotNO,A.BaseQty
			HAVING SUM(ISNULL(B.Qty,0))<A.BaseQty*@paol
			
			IF @StationNo IS NOT NULL AND @SLotNO IS NOT NULL
			 BEGIN
				SET @I_ReturnMessage='ServerMessage: 工单【'+@MOName+'】在机台【'+@StationNo+'】的槽位【'+@SLotNO+'】处的物料数量【'+CONVERT(NVARCHAR(10),ISNULL(@sumQty,0))+'】不足单位用量【'+CONVERT(NVARCHAR(10),ISNULL(@BaseQty,0))+'*'+CONVERT(NVARCHAR(10),@LotSNCount)+'】('+@ABSide+'面)1!'
				SET @I_ExceptionFieldName='LotSN'
				SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
				RETURN -1
			 END
			
		 END	
     END


	   declare @returnvalues int
	declare @LotSNList nvarchar(max)
	set @LotSNList=@LotSN
	exec @returnvalues=Proc_RegisterDoingSN @I_ReturnMessage=@I_ReturnMessage output, @LotSNList=@LotSNList,  @SP='Txn_SMTIssueExeNew_JM' ,@Status=1 --标注此批SN正在处理 
	if @returnvalues=-1
	begin

		SET @I_ReturnMessage='ServerMessage: '+ISNULL(@I_ReturnMessage,'')+'(重复提交已忽视)'+@LotSN
		SET @I_ExceptionFieldName='LotSN'
		SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
		return -1
	end

    
    DECLARE @bindLotSNRowNum INT=1
    DECLARE @bindLotSN TABLE
    (
		LotSN NVARCHAR(50),
		ProductLotSN NVARCHAR(50),
		Qty DECIMAL(18,4),
		rowNum INT
    )
    
    BEGIN TRY  --扣料

		
		DECLARE @AssyDataChainId CHAR(12)
		DECLARE @LotProductId CHAR(12)
		DECLARE @LotQty DECIMAL(18,4)
		
		DECLARE @i1 INT
		DECLARE @i2 INT
		DECLARE @s1 INT
		DECLARE @s2 INT
		
		DECLARE @tmp TABLE
		(
			LotOnSMTId CHAR(12),
			LotId CHAR(12),
			LotSN NVARCHAR(50),
			Qty DECIMAL(18,4),
			_SMTMountLotRowNum INT,
			RowNum INT
		)
		
		DECLARE @tLotOnSMTId CHAR(12)
		DECLARE @tLotId CHAR(12)
		DECLARE @tLotSN NVARCHAR(50)
		DECLARE @tQty DECIMAL(18,4)
		DECLARE @t_SMTMountLotRowNum INT
		DECLARE @IssyQty DECIMAL(18,4)
		
		DECLARE @DataChainAssyIssueId CHAR(12)
		DECLARE @IssueDataChainId CHAR(12)
		
		DECLARE @CheckQty DECIMAL(18,4)
		DECLARE @NONWorkflowStepId CHAR(12)
		DECLARE @UserComment NVARCHAR(50)
		
		SELECT @NONWorkflowStepId = WorkflowStepID 
		      FROM workflowstep WITH(NOLOCK) 
		      WHERE WorkflowId = @WorkflowID AND Specificationid ='SPE10000008G'  ---- ZOWEE-SMT-PCB第二次投板
		
		--IF ISNULL(@NONWorkflowStepId,'')=''
		-- BEGIN
		--	DECLARE @wn NVARCHAR(50)
		--	SELECT @wn=ISNULL(dbo.WorkflowRoot.WorkflowName,'N/A') FROM dbo.Workflow WITH(NOLOCK) 
		--	LEFT JOIN dbo.WorkflowRoot WITH(NOLOCK) ON dbo.Workflow.WorkflowRootId = dbo.WorkflowRoot.WorkflowRootId
		--	WHERE WorkflowId=@WorkflowID
			
		--	SET @I_ReturnMessage='ServerMessage:工作流【'+@wn+'】中没有找到二次投板节点!'
		--	RAISERROR(@I_ReturnMessage,16,1)
		-- END
IF @MOId IN ('MOD100004SPT','MOD100004SWF')
BEGIN
   IF @Isbug=1
   BEGIN
      INSERT INTO dbo.CatchErooeLog
              ( ProcName ,ErooeCommad , CreateDate ,Duration)
      VALUES  ( N'Txn_SMTIssueExeNew_JM' , -- ProcName - nvarchar(50)
                N'2' , -- ErooeCommad - nvarchar(500)
                GETDATE() , -- CreateDate - datetime
                DATEDIFF(MILLISECOND,@ResultTime,GETDATE()) 
              )
	  SET @ResultTime=GETDATE()
   END
END			
			DECLARE @DataChainTable TABLE
		(
			DataChainId CHAR(12),
			LotId CHAR(12),
			MOId CHAR(12),
			ProductId CHAR(12),
			Qty DECIMAL(18,4),
			SpecificationId CHAR(12),
			WorkflowStepId CHAR(12),
			TxnCode VARCHAR(10),
			MOItemId CHAR(12)
		)
		DECLARE @DataChainAssyIssueTable TABLE
		(
			DataChainAssyIssueId CHAR(12),
			AssyDataChainId CHAR(12),
			IssueDataChainId CHAR(12),
			AssyIssueType CHAR(1),
			AssyMOID CHAR(12),
			AssyLotId CHAR(12),
			IssueLotId CHAR(12),
			IssueQty DECIMAL(18,4),
			ResourceId CHAR(12),
			UserId CHAR(12),
			SpecificationId CHAR(12),
			WorkflowStepId CHAR(12),
			IsReplaceProduct BIT
		)
		DECLARE @LotTable TABLE
		(
			LotId CHAR(12),
			Qty DECIMAL(18,4)
		)
		DECLARE @LotOnSMTTable TABLE
		(
			LotOnSMTId CHAR(12)
		)
		
		DECLARE @DataChainMove TABLE 
		(
			DataChainMoveId CHAR(12),
			DataChainId CHAR(12),
			LotId CHAR(12),
			MOId CHAR(12),
			MOItemId CHAR(12),
			Qty CHAR(12),
			NonStdMoveReasonId CHAR(12),
			IsNonStdMove BIT,
			WorkflowStepId CHAR(12),
			ToWorkflowStepId CHAR(12),
			WorkflowId CHAR(12),
			ToWorkflowId CHAR(12),
			LotInDate DATETIME,
			LotOutDate DATETIME,
			CycleTime1 DECIMAL(18,4),
			CycleTime2 DECIMAL(18,4)
		 )
		
		DECLARE 
		@MoveMOId CHAR(12),
		@MoveMOItemId CHAR(12),
		@MoveWorkflowId CHAR(12),
		@MoveLatestMoveDate DATETIME,
		@MoveSpecificationId CHAR(12),
		@MoveWorkflowStepId CHAR(12),
		@LatestMoveDate DATETIME
		
		SET @i=1
		WHILE @i<=@LotSNCount
		 BEGIN
			IF	@paol<>0
			BEGIN
				SELECT @LotId=LotId,@LotSN=LotSN,@LotProductId=ProductId,@LotQty=Qty,
					   @MoveMOId=MOId,@MoveMOItemId=MOItemId,@MoveWorkflowId=WorkflowId,@MoveLatestMoveDate=LatestMoveDate,
					   @MoveSpecificationId=SpecificationId,@MoveWorkflowStepId=WorkflowStepId,
					   @LatestMoveDate=LatestMoveDate
				 FROM @LinkLotSN WHERE RowNum=1
			END
			ELSE	
			BEGIN
			SELECT @LotId=LotId,@LotSN=LotSN,@LotProductId=ProductId,@LotQty=Qty,
				   @MoveMOId=MOId,@MoveMOItemId=MOItemId,@MoveWorkflowId=WorkflowId,@MoveLatestMoveDate=LatestMoveDate,
				   @MoveSpecificationId=SpecificationId,@MoveWorkflowStepId=WorkflowStepId,
				   @LatestMoveDate=LatestMoveDate
			 FROM @LinkLotSN WHERE RowNum=@i
			END
			EXEC SysGetObjectPKid '','DataChain',@AssyDataChainId OUTPUT
			INSERT INTO @DataChainTable
			        ( DataChainId ,
			          LotId ,
			          MOId ,
			          ProductId ,
			          Qty ,
			          SpecificationId ,
			          WorkflowStepId,
			          TxnCode,MOItemId
			        )
			VALUES  ( @AssyDataChainId , -- DataChainId - char(12)
			          @LotId , -- LotId - char(12)
			          @MOID , -- MOId - char(12)
			          @LotProductId , -- ProductId - char(12)
			          @LotQty , -- Qty - decimal
			          @SpecificationId , -- SpecificationId - char(12)
			          @WorkflowStepId,  -- WorkflowStepId - char(12)
			          'SMTASSY',@MoveMOItemId
			        )

					
			IF @IsSMTMountRequired='true' --循环扣料
			 BEGIN
				SELECT @s1=COUNT(1),@i1=1 FROM @_StationNoSlot
				
				WHILE @i1<=@s1  --循环料站表，找出依次要扣的物料
				 BEGIN
					IF	@paol<>0 AND @xiaob <>0
					BEGIN
						SELECT @StationNo=StationNO,
						   @SLotNO=SLotNO,
						   @BaseQty=BaseQty*@paol 
						   --@BaseQty=BaseQty
					   FROM @_StationNoSlot 
					   WHERE RowNum=@i1
					END
					ELSE
					begin
						SELECT @StationNo=StationNO,
						   @SLotNO=SLotNO,
						   @BaseQty=BaseQty 
					   FROM @_StationNoSlot 
					   WHERE RowNum=@i1
					END
					
					
					DELETE @tmp
					
					SET  @temp_issueqty=0
					
					INSERT INTO @tmp --得到要扣料的物料列表
					SELECT LotOnSMTId,LotId,LotSN,CASE WHEN Qty<=0 THEN 0 ELSE Qty END AS Qty,
						   RowNum AS _SMTMountLotRowNum,
						   ROW_NUMBER()OVER(ORDER BY LotOnSMTId ASC) AS RowNum
					   FROM @_SMTMountLot
					   WHERE StationNO=@StationNo
						 AND SLotNO=@SLotNO
						 AND Qty>0
					   ORDER BY CreateDate ASC
	 				
					SELECT @s2=COUNT(1),@i2=1 FROM @tmp 
					
					WHILE @i2<=@s2 --循环扣料
					 BEGIN
					 
						SELECT @tLotOnSMTId=LotOnSMTId,
							   @tLotId=LotId,
							   @tLotSN=LotSN,
							   @tQty=Qty,
							   @t_SMTMountLotRowNum=_SMTMountLotRowNum 
						   FROM @tmp WHERE RowNum=@i2
				
						IF @BaseQty>@tQty
						 BEGIN
							SET @IssyQty=@tQty
						    SET @temp_issueqty=@IssyQty+@temp_issueqty
						 END
						ELSE
						 BEGIN
							SET @IssyQty=@BaseQty-@temp_issueqty
							SET @temp_issueqty=@IssyQty+@temp_issueqty
						 END
						 
						INSERT INTO @bindLotSN
						SELECT @LotSN AS LotSN,
						       @tLotSN AS ProductLotSN,
						       @IssyQty AS Qty,
						       @bindLotSNRowNum AS rowNum
						       
						SET @bindLotSNRowNum=@bindLotSNRowNum+1
						 
						--产生数据链
						EXEC SysGetObjectPKid '','DataChain',@IssueDataChainId OUTPUT
						INSERT INTO @DataChainTable
										( DataChainId ,
										  LotId ,
										  MOId ,
										  ProductId ,
										  Qty ,
										  SpecificationId ,
										  WorkflowStepId,
										  TxnCode,MOItemId
										)
								VALUES  ( @IssueDataChainId , -- DataChainId - char(12)
										  @tLotId , -- LotId - char(12)
										  @MOID , -- MOId - char(12)
										  @SMTProductId , -- ProductId - char(12)
										  @IssyQty , -- Qty - decimal
										  @SpecificationId , -- SpecificationId - char(12)
										  @WorkflowStepId,  -- WorkflowStepId - char(12)
										  'SMTISSUE',''
										)
								
						--装配明细
							EXEC SysGetObjectPKid '','DataChainAssyIssue',@DataChainAssyIssueId  OUTPUT
						INSERT INTO @DataChainAssyIssueTable  (
												DataChainAssyIssueId,
												AssyDataChainId,
												IssueDataChainId,
												AssyIssueType,
												AssyMOID,
												AssyLotId,
												IssueLotId,
												IssueQty,
												ResourceId,
												UserId,
												SpecificationId,
												WorkflowStepId,
												IsReplaceProduct
											)
										VALUES(
												@DataChainAssyIssueId,
												@AssyDataChainId,
												@IssueDataChainId,
												'',
												@MOID,
												@LotId,
												@tLotId,
												@IssyQty,
												@I_ResourceId,
												@I_OrBitUserId,
												@SpecificationId,
												@WorkflowStepId,
												'false'
											) 
											
						--UPDATE Lot SET @CheckQty=Qty,
						--			   Qty=Qty-@IssyQty,
						--			   LatestActivityDate=GETDATE()
						--		 WHERE LotId=@tLotId
						IF EXISTS(SELECT 1 FROM @LotTable WHERE LotId=@tLotId)
						 BEGIN
							UPDATE @LotTable SET Qty=ISNULL(Qty,0)+@IssyQty WHERE LotId=@tLotId
						 END
						ELSE
						 BEGIN
							INSERT INTO @LotTable(LotId,Qty)VALUES(@tLotId,@IssyQty)
						 END
						--IF @CheckQty>=0 AND @CheckQty!=@tQty
						-- BEGIN
						--	SET @I_ReturnMessage='ServerMessage:物料批号【'+ISNULL(@tLotSN,'N/A')+'】数量发生了改变(原始数量为：'+CONVERT(NVARCHAR(50),@tQty)+'	现在数量为：'+CONVERT(NVARCHAR(50),@CheckQty)+'),导致扣料失败!'
						--	RAISERROR(@I_ReturnMessage,16,1)
						-- END
						UPDATE @_SMTMountLot SET Qty=Qty-@IssyQty WHERE LotId=@tLotId
						
					    UPDATE @tmp SET Qty=Qty-@IssyQty WHERE LotId=@tLotId
					    
						IF @IssyQty>=@tQty
						 BEGIN
							--DELETE dbo.LotOnSMT WHERE LotOnSMTId=@tLotOnSMTId
							INSERT INTO @LotOnSMTTable(LotOnSMTId)VALUES(@tLotOnSMTId)
						 END
					    
						IF @BaseQty-@temp_issueqty=0
						 BEGIN
							BREAK
						 END
						
						SET @i2=@i2+1
					 END
					 
					SET @i1=@i1+1
				 END
		     END
		  	
			
				
		    IF	 @paol=0  OR @xiaob<>0
			BEGIN
						DECLARE @MoveDataChainId CHAR(12)
				EXEC SysGetObjectPKid '','DataChain',@MoveDataChainId OUTPUT
				INSERT INTO @DataChainTable
				        ( DataChainId ,
				          LotId ,
				          MOId ,
				          MOItemId ,
				          Qty ,
				          TxnCode ,
				          ProductId ,
				          SpecificationId ,
				          WorkflowStepId 
				        )
				VALUES(
						  @MoveDataChainId,
						  @LotId,
						  @MoveMOId,
						  @MoveMOItemId,
						  @LotQty,
						  'MOVE',
						  @LotProductId,
						  @ToSpeicifcationId,
						  @ToWorkflowStepId
						  
				)
				
				DECLARE @MoveDataChainMoveId CHAR(12)
				EXEC SysGetObjectPKid '','DataChainMove',@MoveDataChainMoveId OUTPUT
				INSERT INTO @DataChainMove  (
								DataChainMoveId ,
								DataChainId ,
								LotId ,
								MOId ,
								MOItemId ,
								Qty ,
								NonStdMoveReasonId ,
								IsNonStdMove ,
								WorkflowStepId ,
								ToWorkflowStepId ,
								WorkflowId ,
								ToWorkflowId ,
								LotInDate ,
								LotOutDate ,
								CycleTime1,
								CycleTime2 
								)
							VALUES
							(
								@MoveDataChainMoveId,
								@MoveDataChainId,
								@LotId,
								@MoveMOId,
								@MoveMOItemId,
								@LotQty,
								'',
								0,
								@MoveWorkflowStepId,
								@ToWorkflowStepId,
								@MoveWorkflowId,
								@MoveWorkflowId,
								GETDATE(),
								GETDATE(),
								CAST(GETDATE()-@LatestMoveDate AS DECIMAL(18,3)) ,
								0
							)
			END
			
			SET @i=@i+1
		 END
		UPDATE dbo.Lot SET Qty=CASE WHEN Lot.Qty>A.Qty THEN Lot.Qty-A.Qty ELSE 0 END
		FROM dbo.Lot INNER JOIN @LotTable A ON Lot.LotId=A.LotId

		------飞达扣数插入数据表，代理扣数20170601 Jason.wang 
		IF  @ShortName  IN ('S01','S02','S03','S04','S05','S06','S14','S15','S16','S18','S19','S20','S26','S27','S28','S34','S35')
		BEGIN
			INSERT INTO dbo.LotOnSMTDeviceParts
					( LotOnSMTId, LotId, Qty,FeederId,Station,WorkcenterName, Status )
			SELECT LotOnSMT.LotOnSMTId,b.LotId,b.Qty,FeederId,StationNO+SLotNO AS Station,WorkcenterName,'0' AS Station  FROM dbo.LotOnSMT WITH(NOLOCK) INNER JOIN @lottable b ON dbo.LotOnSMT.LotId=b.lotid
			INNER JOIN dbo.WorkCenter WITH(NOLOCK) ON ShortName=SMTLineNO  
			WHERE MOId=@moid AND SMTLineNO=@ShortName  AND  ISNULL(FeederId,'')<>'' 			
		END	


				
		DELETE LotOnSMT WHERE EXISTS(SELECT 1 FROM @LotOnSMTTable WHERE LotOnSMTId=LotOnSMT.LotOnSMTId)
		INSERT INTO dbo.DataChain
				        ( DataChainId ,
				          LotId ,
				          MOId ,
				          MOItemId ,
				          Qty ,
				          TxnCode ,
				          ProductId ,
				          UserId ,
				          WorkcenterId ,
				          ResourceId ,
				          ShiftId ,
				          SpecificationId ,
				          WorkflowStepId ,
				          PluginId ,
				          CreateDate
				        )
				SELECT DataChainId,
					   LotId,
					   MOId,
					   MOItemId,
					   Qty,
					   TxnCode,
					   ProductId,
					   @I_OrBitUserId,
					   @WorkcenterId,
					   @I_ResourceId,
					   '',
					   SpecificationId,
					   WorkflowStepId,
					   @I_PlugInCommand,
					   GETDATE()
				FROM @DataChainTable
		
		INSERT INTO dbo.DataChainAssyIssue
				        (   DataChainAssyIssueId,
							AssyDataChainId,
							IssueDataChainId,
							AssyIssueType,
							AssyMOID,
							AssyLotId,
							IssueLotId,
							IssueQty,
							ResourceId,
							UserId,
							SpecificationId,
							WorkflowStepId,
							IsReplaceProduct
				        )
				SELECT  DataChainAssyIssueId,
						AssyDataChainId,
						IssueDataChainId,
						AssyIssueType,
						AssyMOID,
						AssyLotId,
						IssueLotId,
						IssueQty,
						ResourceId,
						UserId,
						SpecificationId,
						WorkflowStepId,
						IsReplaceProduct
				FROM @DataChainAssyIssueTable
			
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
			SELECT DataChainMoveId,
				   DataChainId,
				   LotId,
				   MOId,
				   MOItemId,
				   Qty,
				   '' AS NonStdMoveReasonId,
				   0 AS IsNonStdMove,
				   WorkflowStepId,
				   ToWorkflowStepId,
				   @I_ResourceId AS ResourceId,
				   @I_ResourceId AS ToResourceId,
				   WorkflowId,
				   ToWorkflowId,
				   '',
				   '',
				   LotInDate,
				   LotOutDate,
				   CycleTime1,
				   CycleTime2,
				   @I_OrBitUserId AS UserId
			FROM @DataChainMove 	 

		IF	 @paol=0  OR @xiaob<>0
		BEGIN
			UPDATE dbo.Lot
			SET WorkFlowStepID=@ToWorkflowStepId,
				SpecificationId=@ToSpeicifcationId,
				WorkCenterId=@WorkCenterId,
				NextWorkFlowStepID=@ToNextWorkflowStepId,
				PreviousWorkflowStepId=WorkflowStepId,
				LatestTxnCode='DC',						
				ResourceID=@I_ResourceId,
				LatestUserId=@I_OrBitUserId,
				ShiftID='',
				LatestMoveDate=GETDATE(),
				LatestActivityDate=GETDATE()
			WHERE EXISTS
			(
				SELECT 1 FROM @LinkLotSN WHERE LotId=Lot.LotId
			)
			
			--增加工单的投入数量统计  2014-6-11
			DECLARE @PCBQty INT
			IF EXISTS (SELECT 1 FROM @LinkLotSN WHERE LotSN=ProductionLot)
			BEGIN
				SELECT @PCBQty=MakeUpCount FROM @LinkLotSN WHERE LotSN=ProductionLot
			END
			ELSE
			BEGIN
				SELECT @PCBQty=COUNT(1) FROM @LinkLotSN WHERE LotSN!=ProductionLot
			END
			
			IF EXISTS(SELECT 1 FROM dbo.WorkflowStep  WITH(NOLOCK)
					 WHERE WorkflowStepId=@WorkflowStepId AND IsStartWorkflowStep=1)
			BEGIN
				UPDATE dbo.MO SET MoQtyInput=ISNULL(MoQtyInput,0)+@PCBQty WHERE MOId=@MOId
			END
			
		END
		IF @IsHuaWeiCustomer='true' --如果是华为客户,上传记录到华为表
		 BEGIN
			BEGIN TRY
				DECLARE @ih INT=1
				DECLARE @sh INT
				
				DECLARE
				@hLotSN NVARCHAR(50),
				@hProductLotSN NVARCHAR(50),
				@hQty DECIMAL(18,4)
				
				SELECT @sh=COUNT(1) FROM @bindLotSN
				
				WHILE @ih<=@sh
				 BEGIN
					SELECT @hLotSN=LotSN,
						   @hProductLotSN=ProductLotSN,
						   @hQty=Qty
						FROM @bindLotSN WHERE rowNum=@ih
						
						
						--修改不上传华为 在板边装车关联子条码时候上传华为
						
						INSERT  INTO  [TE].dbo.TABLEFORTR_LOT_BB
					        ( motherlot, mzlotsn, qty, moname )
					VALUES  (@hLotSN, -- lotsn - nvarchar(100)
					         @hProductLotSN, -- mzlotsn - nvarchar(100)
					         @hQty, -- qty - numeric
					         @MOName  -- moname - nvarchar(50)
					          )
					
						
					--INSERT  INTO  [10.2.0.8].HUAWEI.dbo.TABLEFORTR_LOT_BB
					--        ( motherlot, mzlotsn, qty, moname )
					--VALUES  (@hLotSN, -- lotsn - nvarchar(100)
					--         @hProductLotSN, -- mzlotsn - nvarchar(100)
					--         @hQty, -- qty - numeric
					--         @MOName  -- moname - nvarchar(50)
					--          )
					
					
					
						--EXEC dbo.Interface_HuaWei_IINVSUMTMP4D @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
						--@RAW_LOT_ID = @hProductLotSN, -- nvarchar(128)
						--@EMS_ORDER_ID = @MOName, -- nvarchar(25)
						--@LOT_ID = @hLotSN, -- nvarchar(30)
						--@USE_QTY = @hQty -- decimal	
					
					
					
					
					SET @ih=@ih+1
				 END
			END TRY 
			BEGIN CATCH
				insert into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SMTIssueExeNew_JM_Huawei',ISNULL(ERROR_MESSAGE(),'上传到华为记录表中失败2')+ ' ' + ISNULL(@I_ReturnMessage,'')) -- add by ybj 20141018
				SET @I_ReturnMessage='ServerMessage: 批号【'+@LotSN+'】贴片成功,但上传到华为记录表中失败2!  '
				SELECT  0 AS I_ReturnValue,@I_ReturnMessage as I_ReturnMessage
				RETURN 0 
			END CATCH 
		 END
		
    END TRY	
    BEGIN CATCH

		SET @I_ReturnMessage='ServerMessage: '+ISNULL(ERROR_MESSAGE(),'扣料出错异常,请重试!')
		SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
		RETURN -1
    END CATCH 
    
    
    exec @returnvalues=Proc_RegisterDoingSN @I_ReturnMessage=@I_ReturnMessage output, @LotSNList=@LotSNList,  @SP='Txn_SMTIssueExeNew_JM' ,@Status=0 --标注此批SN已处理完成

	 ----统计产出--------
    DECLARE  @DATE_4D  DATETIME=GETDATE()
    EXEC Txn_smtTiePian_chanchu_4d
	@I_ResourceId = @I_ResourceId,		--资源ID(如果资源不在资源清单中，那么它将是空的)
	@I_ResourceName=@I_ResourceName,
	@flag =2, ---1  普通连扳  2板边
	@LotId = @LotId, -- char(12)
	@MOId = @MOId, -- char(12)
	@WorkcenterId = @WorkcenterId, -- char(12)
	@SpecificationId = @SpecificationId, -- char(12)
	@ShiftId = '', -- char(12)
	@DateTime = @DATE_4D
   ----统计产出--------


	BEGIN TRY
		EXEC dbo.Txn_IntervalStaticOfTP 
			@LotId = @IntervalotId, -- char(12)
		    @ResourceId = @I_ResourceId -- char(12)	
	END TRY
	BEGIN CATCH
		PRINT ERROR_MESSAGE()
	END CATCH 
 IF @MOId IN ('MOD100004SPT','MOD100004SWF')
BEGIN
   IF @Isbug=1
   BEGIN
      INSERT INTO dbo.CatchErooeLog
              ( ProcName ,ErooeCommad , CreateDate ,Duration)
      VALUES  ( N'Txn_SMTIssueExeNew_JM' , -- ProcName - nvarchar(50)
                N'5' , -- ErooeCommad - nvarchar(500)
                GETDATE() , -- CreateDate - datetime
                DATEDIFF(MILLISECOND,@ResultTime,GETDATE()) 
              )
	  SET @ResultTime=GETDATE()
   END
END	   
    
    SET  @I_ReturnMessage='ServerMessage: 批号【'+@LotSN+'】贴片成功!  '
	SET @I_ExceptionFieldName='LotSN'
	SELECT  0 AS I_ReturnValue,@I_ReturnMessage as I_ReturnMessage
	RETURN 0 
END