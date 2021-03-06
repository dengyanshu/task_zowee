USE [OrBitX]
GO
/****** Object:  StoredProcedure [dbo].[Txn_SprayingScan_Batch]    Script Date: 2018-5-14 8:38:10 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		<MES Team ChenZH >
-- Create date: <2013.12.10>
-- Description:	<SMT贴片上线扫描 整个连板提交>
-- Rev: 10.01  add by luoll 20150421 所有工单都需要管控锡膏，出锡膏房24小时内才能用，且绑定PCB条码
-- =============================================
ALTER PROCEDURE [dbo].[Txn_SprayingScan_Batch]
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

@MOId					nchar(12)='',				--工单ID
@MOName					nvarchar(50)='',            --工单编号
@MakeupCount			int=0,						--拼板数
@CellId					nvarchar(50)='',		    --叉板位置	
@SNScan					nvarchar(100)='',			--扫描SN
@LotSNList				nvarchar(1000)='',			--LotSN清单逗号分割的多个LOTSN
@HideSN					nvarchar(max)='',			--隐藏SN
@ProductName			nvarchar(50)='',       		--料号
@ScanCount				INT =0,                  	--已扫描数
@PCBType				nvarchar(20) = '',			--PCB板类型(阴阳板/AB面板)
@ABSide					nvarchar(10) = '',			--A面/B面
@PCBSN					nvarchar(50) = '',          --PCB板SN
@PCBQty					int = 0,					--PCB数量
@SMTLabelType			nvarchar(50) = '',			--SMT贴片标签
@ASideQty				int = 0,
@BSideQty				int = 0,
@ForebodeCount			int =0,						--预设定的连板数 --2013.11.22 拼板数不能大于预设定的连板数 陈宗海添加
@TinolSN				NVARCHAR(50)=''                           --20140517 xuzl 锡膏 条码

as
begin
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	
	Declare @V_CHARS nvarchar(50)
	Declare @V_Rule nvarchar(50)
	
	declare @count					int=0	--传入的连板LotSn 数
	declare	@i						int=1	--供循环用的下标
	declare @WorkflowId				char(12)
	declare @return_value			int --是否启动成功:0成功;非0失败
	declare @Date					varchar(50)
	declare @parentid				char(12)
    DECLARE @LotSN					varchar(50)
    declare @MOScanCount			INT	--工单已扫描数
    declare @ProductId				char(12)
    Declare @MOPCBType				nvarchar(50)
    Declare @PCBLotID				char(12)
    Declare @PCBProductID			char(12)
    Declare @LotID					char(12)
    Declare @MOQtyRequired			int
    declare @Lot_SpecificationId	char(12)
    declare @Lot_SpecificationName	nvarchar(50)
    declare @SNType					nvarchar(50)
    
	DECLARE @CustomerId				CHAR(12)
	DECLARE @WOSN					NVARCHAR(50)
	DECLARE @IsHuaWeiCustomer		BIT
    
    Declare @NextWorkflowStepId		char(12)
    Declare @LotStatus				CHAR(1)
	Declare	@ListLotId				nvarchar(max)
	DECLARE @Sql					NVARCHAR(500)	--动态SQL
	DECLARE @recipients				NVARCHAR(MAX) --收件人
	DECLARE  @copy_recipients		NVARCHAR(MAX)	--抄送人
	DECLARE @IsJITMode BIT
	
	
	DECLARE @debug NVARCHAR(50) 
	SET @debug = @LotSNList
	DECLARE @if_debug BIT ='false'--false
    DECLARE @ProductIdMO CHAR(12)=''
	DECLARE @IsCheck CHAR(2)='1'	
	-- add by ybj 20150224
	
	--IF @MOId ='MOD10000619U'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('757', @PCBSN )
	
   IF @if_debug = 'true'
         INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_debug_1', @debug+'_'+@MOName )
	

	
	
	DECLARE  @LotSNList4d  NVARCHAR(MAX)
	SET @LotSNList4d=@LotSNList  

	--if ISNULL(@MOId,'n/a')='MOD100004BV6' or ISNULL(@MOName,'n/a')='MO060116040360'
	--begin
	--	set @I_ReturnMessage='ServerMessage:TEST1'
	--	return -1
	--end
    -------------------------------------------------------------基本数据验证

	---直接以工单去查找是否有联络单OA---
	DECLARE  @ecnno NVARCHAR(100)
	DECLARE  @QC_CONFIRM_USER NVARCHAR(100)
	DECLARE @TE_CONFIRM_USER   NVARCHAR(100)
	SELECT  @ecnno=ECN_NO, @QC_CONFIRM_USER=QC_CONFIRM_USER,@TE_CONFIRM_USER=TE_CONFIRM_USER
	FROM   [10.2.0.25].OrbitXU9.dbo.erp_cn_new  WITH(NOLOCK) WHERE ECN_EFFECT_MO=@moname
	IF  ISNULL(@ecnno,'')<>'' AND  CHARINDEX('LLD',@ecnno,0)<>0
	BEGIN
	    SET @I_ReturnMessage='ServerMessage:ECN失败！工单有在OA做过联络通知单,工程审核人：['+CASE WHEN ISNULL(@TE_CONFIRM_USER,'')='' THEN '无' ELSE  @TE_CONFIRM_USER END  +'],品质审核人:['+
		CASE WHEN ISNULL(@QC_CONFIRM_USER,'')='' THEN '无' ELSE  @QC_CONFIRM_USER END +'],工单为['+@moname+'],ECN单号为:['+@ecnno+']'
		RETURN -1
	END
	---直接以工单去查找是否有联络单OA---
   
	----检查料号的ECN变更通知单---
	--DECLARE  @ecnno2 NVARCHAR(100)
	--DECLARE  @QC_CONFIRM_USER2 NVARCHAR(100)
	--DECLARE @TE_CONFIRM_USER2   NVARCHAR(100)
	--DECLARE  @ECN_EFFECT_MO  NVARCHAR(200)
	--SELECT  @ecnno2=ECN_NO, @ECN_EFFECT_MO=ECN_EFFECT_MO,@QC_CONFIRM_USER2=QC_CONFIRM_USER,@TE_CONFIRM_USER2=TE_CONFIRM_USER
	--FROM   [10.2.0.25].OrbitXU9.dbo.erp_cn_new WITH(NOLOCK) WHERE ProductName=@productname

	--IF  ISNULL(@ecnno2,'')<>'' AND    EXISTS(SELECT 1 FROM (SELECT  id  FROM dbo.SQL_split(@ECN_EFFECT_MO,'')) A WHERE A.id=@moname) --AND @MOName<>'MO060116040360'
	--BEGIN
	--    SET @I_ReturnMessage='ServerMessage:ECN失败！工单有在OA做过ECN变更通知单,工程审核人：['+CASE WHEN ISNULL(@QC_CONFIRM_USER2,'')='' THEN '无' ELSE  ISNULL(@TE_CONFIRM_USER2,'无') END  +'],品质审核人:['+
	--	CASE WHEN ISNULL(@QC_CONFIRM_USER2,'')='' THEN '无' ELSE  ISNULL(@TE_CONFIRM_USER2,'无') END +'],工单为['+@moname+'],ECN单号为:['+@ecnno2+']'
	--	--SET @I_ReturnMessage='ServerMessage:ECN失败'+@productname
	--	RETURN -1
	--END
	--检查料号的ECN变更通知单---
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_debug_1_2', @debug +'_'+@MOName)

    if ISNULL(@ABSide,'') = '' 
    begin
		set @I_ReturnMessage='ServerMessage: A/B面不能为空，请输入要贴片的面!'
		return -1
	end
	if LTRIM(RTRIM(@ABSide))<>'A' and LTRIM(RTRIM(@ABSide))<>'B'
    begin
		set @I_ReturnMessage='ServerMessage: 请输入要贴片的面!  且必须是A或者B    '+@ABSide
		return -1
	end
    
    if isnull(@PCBType,'') = 'AB面板' and ISNULL(@ABSide,'') = ''
    begin
		set @I_ReturnMessage='ServerMessage: 如果PCB板类型为AB面板，请输入最先贴片的面,A面还是B面!'
		return -1
	end
	
	if isnull(@PCBType,'') = '阴阳板' and ISNULL(@ABSide,'') <> 'A'
    begin
		set @I_ReturnMessage='ServerMessage: 如果PCB板类型为阴阳板，要求先贴片A面!'
		return -1
	end

	if isnull(@PCBType,'') = '阴阳板' and (isnull(@ASideQty,'') = '' or ISNULL(@BSideQty,'') = '')
    begin
		set @I_ReturnMessage='ServerMessage: 如果PCB板类型为阴阳板，必须输入A面数量和B面数量!'
		return -1
	end
	
	if isnull(@PCBType,'') = '阴阳板' and CONVERT(int,@ASideQTY+@BSideQTY) <> CONVERT(int,@MakeupCount)
	begin
		set @I_ReturnMessage='ServerMessage: 如果PCB板类型为阴阳面板，A面板数加B面板数必须等于连板数!'
		return -1
	end
    IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_debug_1_3', @debug +'_'+@MOName)
			 
    select @MOPCBType = PCBTYPE, @CustomerId=MO.CustomerId,
			   @WOSN=MO.WOSN,@SNType=MO.SNType,@IsJITMode=IsJITMode,@ProductIdMO=ProductId from mo WITH(NOLOCK) where MOId = @MOID
    --20170726 xiezq 小板不卡，主板卡，同任务令
    IF EXISTS(SELECT 1 FROM dbo.Product WITH(NOLOCK)
			INNER JOIN ProductRoot WITH(NOLOCK) ON ProductRoot.ProductRootId = Product.ProductRootId
			WHERE ProductId=@ProductIdMO
			AND ProductSpecification LIKE '%2*2%'
			AND ProductName LIKE '910005%'
			AND ProductDescription='4G路由 SMT2')
	BEGIN
		SET @IsCheck='0'
	END   
    if Isnull(@PCBType,'') <> @MOPCBType
    begin
		set @I_ReturnMessage='ServerMessage: PCB板类型必须与工单PCB板类型一致。'
		return -1
	end

    if not exists(select 1 from mo with(nolock) where MOId = @MOId and MO.MOStatus = 3)
    begin
		set @I_ReturnMessage='ServerMessage: 此工单不存在或未审核!'
		return -1
	END
    
	
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_debug_1_4', @debug +'_'+@MOName)
	DECLARE  @producridmo_4d CHAR(12)
	SELECT @producridmo_4d=ProductId FROM dbo.MO  with(nolock) WHERE MOId=@MOId
	IF  EXISTS(SELECT  1 FROM  dbo.yy_4d WITH(NOLOCK) WHERE productid=@producridmo_4d) 
	BEGIN
	    
		DECLARE  @cus_4d CHAR(12)
		SELECT  @cus_4d=CustomerId  FROM  dbo.Product  WITH(NOLOCK)  WHERE  ProductId=@producridmo_4d
		IF  ISNULL(@cus_4d,'')  NOT IN  ('CUS1000000J4','CUS1000000QL')
		BEGIN
	       set @I_ReturnMessage='ServerMessage: 该工单对应的产品为华技产品，但是产品表中未维护成华技！，请在插件PDIF中重新维护！'
		   RETURN -1
		END
	END
	
	if Isnull(@MakeupCount,'') = ''
	begin
		set @I_ReturnMessage='ServerMessage: 连板数不能为空，请输入!'
		return -1
	END
	
	Declare @WorkcenterId char(12)=NULL
		
	select @WorkcenterId=ISNULL(WorkcenterId,'') from Resource with(nolock) where ResourceId=@I_ResourceId
	IF @WorkcenterId=''
	BEGIN
		SET @I_ReturnMessage = 'ServerMessage: 没有获取到资源的线体，请注册资源！'
		RETURN -1
	END
	----20161118 xiezq 启用刮刀管控L07/L08/L09线
	--IF EXISTS(SELECT 1 FROM dbo.MO  WHERE MOId=@MOId AND WorkcenterId IN ('WKC10000000T','WKC10000000U','WKC10000003J','WKC10000003K','WKC10000003L','WKC10000001T','WKC10000003G',
	--	                      'WKC10000003H','WKC10000003I','WKC10000003Q','WKC10000003S','WKC10000003T'))
	--BEGIN
	--    IF  EXISTS(SELECT 1 FROM SteelOnLine WHERE MOId=@MOId AND ISNULL(ScraperNO,'')='') 
	--	BEGIN
	--		SET @I_ReturnMessage = 'ServerMessage: 此工单没有绑定刮刀，不允许上线，请联系治具管理员确认！'
	--		RETURN -1
	--	END	
	--END	
   


	--------------------------------SMT平板调用   2017-02-13 Lmh 任务令校验 Begin  当任务令不为空并且任务令第五位是W的才判断
	--此功能不允许屏蔽
	--XN虚拟任务令不做管控
	IF LEFT(@WOSN,2)<>'XN' AND @WOSN<>'DPZAE83806E'  
	BEGIN
		DECLARE @ErrorCode nvarchar(MAX)     
		DECLARE @ErrorMessage nvarchar(MAX)
		DECLARE @Query_TaskNo NVARCHAR(50)
		DECLARE @Query_VendorId NVARCHAR(50) 
		DECLARE @Row_End_Time DATETIME
		IF	 ISNULL(@WOSN,'')<>'' AND LEN(@WOSN)=11 AND @IsCheck<>'0'--AND (SUBSTRING(@WOSN,5,1)='W' OR SUBSTRING(@WOSN,5,1)='9')
		BEGIN
			IF NOT EXISTS(SELECT TOP 1 1 FROM dbo.DataChainAssyIssue WITH(NOLOCK) WHERE AssyMOId=@MOID )
			BEGIN
				BEGIN TRY
					--更换接口 liaomh 20170310
					EXEC [dbo].[Huawei_GetProcessdownloadetail_Time]
					@ErrorCode=@ErrorCode OUTPUT,
					@ErrorMessage=@ErrorMessage OUTPUT,
					@Row_End_Time=@Row_End_Time OUTPUT,
					@Query_TaskNo=@WOSN,
					@Query_VendorId='89638'
				END TRY
				BEGIN CATCH
					SET  @I_ReturnMessage='ServerMessage:连接华为网络异常，请联系网络管理员'
					SET @I_ExceptionFieldName='LotSN02'
					RETURN -1
				END CATCH
				IF   ((ISNULL(@ErrorCode,'1')<>'0') OR (ISNULL(@Row_End_Time,'')>GETDATE()) OR (ISNULL(@Row_End_Time,'')<'2010-01-01')) AND  @WOSN  NOT IN ('DPZAK83f46C' ,'DPZAE83L060','DPZAK83P26J','DPZAK83L363','DPZAE83L061','DPZAK83W06X','TPZAWK3256V','DPZAK844364') AND @ProductName NOT IN('910005-4780','910005-4778')  --add by zhougs 2018-03-18 AND @WOSN<>'DPZAK83f46C'  add by baolj 增加按料号卡齐套
				                                                                                                          --DPZAE83L060,'DPZAK83P26J','DPZAK83L363','DPZAE83L061' 20180323 pengly  临时不卡任务令
				BEGIN 
					SET  @I_ReturnMessage='ServerMessage:此任务令【'+ISNULL(@WOSN,'')+'】未能在预计拣料时间内【'+CONVERT(NVARCHAR(50),ISNULL(@Row_End_Time,''),120)+'】齐套发料，请联系生管确认！'
					SET @I_ExceptionFieldName='LotSN02'
					RETURN -1
				END
				ELSE
				BEGIN
					EXEC dbo.Txn_HW_WOSN_Check 
					@WOSN = @WOSN, -- nvarchar(50)
					@EndTime = @Row_End_Time -- datetime
	
				END	 
			END	
		END 
	END 
	--------------------------------2017-02-13 Lmh 任务令校验 End 

	
 -- add by ybj 20150224
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_debug_2', @debug +'_'+@MOName)
	 --add 华为任务令校验
    BEGIN
		EXEC dbo.txn_IsHuaWeiCustomer 
			@CustomerId = @CustomerId, -- char(12)
			@MOID=@MOID,
			@IsHuaWeiCustomer = @IsHuaWeiCustomer OUTPUT -- bit
			
		--IF ISNULL(@IsHuaWeiCustomer,'false')='true' AND ISNULL(@WOSN,'')=''
		-- BEGIN
		--	SET @I_ReturnMessage= 'ServerMessage:工单【'+@MOName+'】是华为工单,请先维护华为工单的任务令(工单信息->标签任务号)!'
		--	SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
		--	RETURN -1
		-- END
    END 
   
    
		--检查锡膏上线管控预警 ADD XUZL 2014-02-18
		BEGIN
			DECLARE @Return INT
			EXEC @Return= Check_TinolOnLine
				 @I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
				 @I_ReturnMessage=@I_ReturnMessage OUTPUT,
				 @Moid=@MOid
	          
			  IF @Return=-1
			   BEGIN
					set @I_ReturnMessage= 'ServerMessage: '+ISNULL(@I_ReturnMessage,'')+'检查锡膏上线不通过'
					RETURN -1
			   end
		END
	-- add by ybj 20150224
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_debug_3', @debug +'_'+@MOName)	
	
	--add by wzq  2013-02-21
	declare @CheckCode nvarchar(50)
	select top 1 @CheckCode=CheckCode from POItemLot with(nolock) where LotSN=@PCBSN
 
	if ISNULL(@CheckCode,'N/A')!='客供料'
	begin
		if @PCBSN not like 'M%'
		Begin
			set @I_ReturnMessage='ServerMessage: 物料PCB板SN扫描错误!'
			return -1
		end
	end
	

    ------判断PCB板是否为空(临时注释)
    if Isnull(@PCBSN,'') = ''
	begin
		set @I_ReturnMessage='ServerMessage: PCB板序列号不能为空，请扫描!'
		return -1
	END
	
	--DECLARE @PCBSN_productid CHAR(12)
	--SELECT @PCBSN_productid=ProductId FROM lot WHERE LotSN=@PCBSN
	
	DECLARE @PCBMOID CHAR(12)
	DECLARE @PCBMONAME NVARCHAR(50)
	select @PCBLotID = LotId,@PCBProductID = Lot.ProductId,@PCBQty = Qty,@WorkflowId = MO.WorkflowID,
			@NextWorkflowStepId=NextWorkflowStepId,@LotStatus=LotStatus,@PCBMOID=dbo.Lot.MOId,@PCBMONAME=MOName
	from lot with(nolock)
	inner  join MO with(nolock) On Lot.MOID = MO.MOID
	INNER JOIN dbo.Product with(nolock) ON dbo.Product.ProductId=lot.ProductId
	--INNER JOIN MOItem ON dbo.MOItem.ProductId=lot.ProductId
	where LotSN = @PCBSN  AND Product.MaterialType='VendorLotSN'   --and Lot.SpecificationId = 'SPE10000004H'  and Qty >0 --物料上线 --喷码扫描节点
	--and MOItem.MOId = @MOID 

	
	-- add 20180312
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad,CreateDate) values('Txn_SprayingScan_Batch_debug_4D_1', @debug +'_'+@MOName,GETDATE())
	

	IF ISNULL(@PCBProductID,'')='' AND NOT EXISTS(SELECT 1 FROM [10.2.0.25].OrBitXE.dbo.PickingListItem WHERE MOId=@MOId AND IssueProductId=@PCBProductID) AND @moid NOT IN('MOD10000550H','MOD10000550L','MOD1000055MG','MOD1000053MY','MOD1000055LS','MOD1000055OB')
	BEGIN
		set @I_ReturnMessage='ServerMessage: 系统不存在此PCB物料，或没有做领料操作5!' + ISNULL(@PCBSN, '')
		return -1	
	END
	 
	 -- add 20180312
	  IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad,CreateDate) values('Txn_SprayingScan_Batch_debug_4D_2', @debug +'_'+@MOName,GETDATE())
	

	IF ISNULL(@IsJITMode,0)=1
	BEGIN
		--add by huangbin 20160830 增加卡工单操作(JIT)

		IF ISNULL(@PCBMOID,'')<>@MOId AND @MOId NOT IN('MOD100005KAX','MOD100005KAZ','MOD1000055OB','MOD100005QDB','MOD100005QEC','MOD100005QFT')
		BEGIN
			set @I_ReturnMessage='ServerMessage: JIT物料，该PCB板对应的工单['+ISNULL(@PCBMONAME,'')+']与选择输入的工单['+ISNULL(@MOName,'')+']不一致，不能操作!' + ISNULL(@PCBSN, '')
			return -1	
		END
	END
	
	 -- add 20180312
	IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad,CreateDate) values('Txn_SprayingScan_Batch_debug_4D_3', @debug +'_'+@MOName,GETDATE())

	IF @moid NOT IN ('MOD100005HXE','MOD100005HVW','MOD100005GCM','MOD100005HPJ','MOD100005IRJ')
	BEGIN
	IF not exists(select top 1 * from MOItem with(nolock) where MOId=@moid and ProductId=isnull(@PCBProductID,'N/A'))
	BEGIN
        IF ISNULL(@IsJITMode,0)!=1 AND NOT EXISTS(SELECT 1 FROM [10.2.0.25].OrBitXE.dbo.PickingListItem WHERE MOId=@MOId AND IssueProductId=@PCBProductID) AND @moid NOT IN('MOD10000550H','MOD10000550L','MOD1000055MG','MOD1000053MY','MOD1000055LS','MOD1000055OB')  --判定是否属于JIT工单,替代下面注释部分 Jason.Wang 2015-04-07
		BEGIN
		  set @I_ReturnMessage='ServerMessage: 发料单不存在此物料1:'+ISNULL(@PCBSN,'N/A') --系统不存在此PCB物料，或没有做领料操作!需检查是否在工单维护时有勾选JIT模式'
		  return -1
		END
	 --   IF @moid not IN  ('MOD100003HVS', 'MOD100003HVV', 'MOD100003HYU', 'MOD100000VND', 'MOD100000VNE','MOD100003K9Y')   ---- 2015.02.10
	 --   BEGIN
		--	set @I_ReturnMessage='ServerMessage:发料单不存在此物料:'+ISNULL(@PCBSN,'N/A') --系统不存在此PCB物料，或没有做领料操作!'
		--	return -1
		--END	
	END
    END

	-- add 20180312
	IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad,CreateDate) values('Txn_SprayingScan_Batch_debug_4D_4', @debug +'_'+@MOName,GETDATE())


 
	if @PCBQty<=0 or @PCBQty is null
	begin
		set @I_ReturnMessage= 'ServerMessage: 该批号无可用数量!' +@PCBSN+'数量'+CONVERT(NVARCHAR(10),@PCBQty)
		return -1
	end

	if @LotStatus<>'1'
	begin
		set @I_ReturnMessage= 'ServerMessage: 该批号处于锁定中!' +@PCBSN
		return -1
	end 

	-- add 20180312
	IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad,CreateDate) values('Txn_SprayingScan_Batch_debug_4D_5', @debug +'_'+@MOName,GETDATE())

	--检查工作流的 开始节点是否为 ZOWEE-SMT-批号启动
	IF ISNULL(@PCBMOID,'')<>'MOD100005RK7'
	BEGIN
	if not exists( select WorkflowStepId  from workflowstep with(nolock) where workflowid=@WorkflowId and SpecificationId='SPE10000004L' and IsStartWorkflowStep=1)
	begin
		set @I_ReturnMessage= 'ServerMessage: 工作流错误!物料对应的工单为：'+@PCBMONAME     --20150315 by qindl 添加工单提示，有时物料对应的工单不正确
		return -1
	END
    END
	SELECT @WorkflowId=WorkflowId FROM MO  with(nolock) WHERE MOId=@MOId

	IF ISNULL(@WorkflowId,'')=''
	BEGIN
		set @I_ReturnMessage= 'ServerMessage: 工作流不存在，请检查工单的工作流是否正确！' 
		return -1
	END 
	if isnull(@WorkflowId,'n/a')='WKF1000000HE' --炉后上线工作流ID
	begin
		set @I_ReturnMessage= 'ServerMessage: 当前工单是炉后上线工作流,不能用此程序上线!' +isnull(@MOName,'n/a')+':'+ISNULL(@WorkflowId,'n/a')
		return -1
	END
	if isnull(@WorkflowId,'n/a')='WKF1000000TM' --板边上线工作流
	begin
		set @I_ReturnMessage= 'ServerMessage: 当前工单是板边上线工作流,不能用此程序上线!' +isnull(@MOName,'n/a')+':'+ISNULL(@WorkflowId,'n/a')
		return -1
	END
 
	--20140321 xuzl Begin
		DECLARE @FirstSide NVARCHAR(50)

		SELECT @FirstSide=FirstSide FROM dbo.Product  WITH(NOLOCK)  WHERE ProductId=@ProductIdMO
		IF ISNULL(@FirstSide,'')='' AND @WorkflowId='WKF1000000IS' --AND @MOId='MOD100002T8R'
		BEGIN
			set @I_ReturnMessage='ServerMessage: 料号中没有维护【贴片顺序】，请联系周斌主管！ '
			return -1
		END
		
		IF ISNULL((SELECT TOP 1 id FROM dbo.SQL_split(ISNULL(@FirstSide,''),'/')),'')<>ISNULL(@ABSide,'') --AND @MOId='MOD100002T8R'
		BEGIN
			set @I_ReturnMessage='ServerMessage: 选择的【A/B面板】与料号中维护的【贴片顺序】不一致，请确认！ '
			return -1
		END

		-- add 20180312
	IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad,CreateDate) values('Txn_SprayingScan_Batch_debug_4D_6', @debug +'_'+@MOName,GETDATE())

  -- add by ybj 20150224
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_debug_5', @debug+'_'+@MOName )
	--20140321 xuzl End
    -------------------------------------------------------------
	declare @TbSnList table
	(
		RowNum				int,
		Lotsn				nvarchar(50),
		LotId				nchar(12),
		SpecificationId		nchar(12),
		WorkflowStepId		nchar(12),
		WorkflowID			nchar(12),
		DataChainId			char(12),
		AssyDataChainId 	char(12),
		IssueDataChainId	char(12)
	)
 	insert into @TbSnList (Lotsn,RowNum) select distinct id ,ROW_NUMBER() OVER (ORDER BY id) AS rowNum
		from SQL_split(@LotSNList,',')
	select  @count=MAX(RowNum) from @TbSnList 	
	---支持MAC
	--select top 1 @LotSN= TbSn.Lotsn  from @TbSnList TbSn  where Lotsn not in (select Lotsn from moitemlot
	--		where   moitemlot.MOId = @MOID and SNTYPE  IN ('PCBASN','MAC'))	
		SELECT  top 1 @LotSN= b.Lotsn  FROM  @TbSnList  b WHERE  NOT  EXISTS(
	SELECT  1  FROM     moitemlot a WITH(NOLOCK)  WHERE  a.moid=@MOID and SNTYPE  IN ('PCBASN','MAC')  AND  a.LotSN=b.lotsn)
	
	
	--IF @LotSN IN (SELECT lotsn FROM moitemlot WHERE   moitemlot.MOId = @MOID and SNTYPE='SN')   --20150321 by qindl
	--BEGIN
	--	DECLARE @MakeUpCount1 INT 
	--	SELECT @MakeUpCount1=MakeupCount FROM PRODUCT WHERE ProductId=@ProductIdMO
	--	SELECT @count=@MakeupCount
	--END

	-- add 20180312
	IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad,CreateDate) values('Txn_SprayingScan_Batch_debug_4D_7', @debug +'_'+@MOName,GETDATE())

	if ISNULL(@LotSN,'')<>''   --AND @LotSN NOT IN ( select Lotsn from moitemlot WHERE   moitemlot.MOId = @MOID and SNTYPE='SN'  --20150321 by qindl 添加and后 板边上线
	begin
		set @I_ExceptionFieldName='SNScan'
			set @I_ReturnMessage='ServerMessage: 此工单不存在此批号，['+@LotSN+']请重新扫描'
			return -1
	end
	if @count<>@MakeupCount
	begin
		set @I_ExceptionFieldName='SNScan'	
		set @I_ReturnMessage='ServerMessage: 当前设定连板数为['+convert(char(10),@MakeupCount)+']与实际连板数['+convert(char(10),@count)+']不相符请检查!'
		return -1
	end	
 

 
	----------------- Liaomh 启动的连扳数量与工单需求数量一致 20170424 ------------------------
	DECLARE @ProductionLotSum INT =0
	DECLARE @MOQtyRequiredSum INT=0
	IF EXISTS (SELECT TOP 1 1 FROM lot WHERE  moid=@moid AND lotsn=ProductionLot AND LEFT(lotsn,2)<>'MZ')
	BEGIN 
		SELECT @MOQtyRequiredSum=MOQtyRequired FROM mo WHERE moid=@moid
		SELECT @ProductionLotSum=(SUM(MakeUpCount)+@MakeUpCount) FROM lot WHERE  moid=@moid AND lotsn=ProductionLot
		IF @ProductionLotSum>@MOQtyRequiredSum
		BEGIN 
			set @I_ExceptionFieldName='SNScan'	
			set @I_ReturnMessage='ServerMessage: 工单['+@moname+']需求数量为：'+CAST(@MOQtyRequiredSum AS NVARCHAR(100))+',与实际启动连扳数量：'+CAST(@ProductionLotSum AS NVARCHAR(100))+'不一致!'
			return -1
		END 
	END 
	----------------- Liaomh 启动的连扳数量与工单需求数量一致 20170424 ------------------------



	----计算PCB板扣数
	if isnull(@PCBSN,'') <> ''
	Begin
		Set @PCBQty = @PCBQty - @MakeupCount
		if  isnull(@PCBQty,0) < 0
		begin
			set @I_ReturnMessage='ServerMessage: 此PCB板序列号数量已用完，请更换物料！'
			return -1
		end
	end
		
	if ISNULL(@SNType,'N/A')='PCBASN'
	begin
		if exists( select lot.LotSN from @TbSnList TbSnList inner join lot with(nolock) on TbSnList.Lotsn=lot.VendorLotSN)
		begin
			--select top 1 @LotSN =lot.lotsn  from @TbSnList TbSnList inner join lot on TbSnList.Lotsn=lot.LotSN
			--set @I_ExceptionFieldName='SNScan'	
			--set @I_ReturnMessage='ServerMessage:批号1：'+@LotSN+'   已经过上线扫描'
			--return -1
			
			----------------------------------------------------------
			set @LotSNList= stuff((select CHAR(10)+','+ltrim(lot.lotsn)  from @TbSnList TbSnList inner join lot with(nolock) on TbSnList.Lotsn=lot.VendorLotSN for xml path('')),1,1,'') 
			set @I_ExceptionFieldName='SNScan'	
			set @I_ReturnMessage='ServerMessage: 批号：'+rtrim(@LotSNList)+'   已经上过线扫描'
			return -1
		end
	end
	else if ISNULL(@SNType,'N/A')='MAC'
	begin
		if exists(select lot.LotSN from @TbSnList TbSnList inner join lot with(nolock) on TbSnList.Lotsn=lot.MAC)
		begin
			select top 1 @LotSN =lot.lotsn  from @TbSnList TbSnList inner join lot with(nolock) on TbSnList.Lotsn=lot.MAC
			set @I_ExceptionFieldName='SNScan'	
			set @I_ReturnMessage='ServerMessage: 批号2：'+isnull(@SNScan,'N/A')+'   已经上过线扫描'
			
			return -1
		end
	END
 -- add by ybj 20150224
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_debug_6', @debug +'_'+@MOName)
	----------------------------------------------------------- 标示连板正在作业
	declare @returnvalues INT =NULL
	declare @LotSNList_a nvarchar(max) =NULL
	set @LotSNList_a=(select top 1 LotSn+',' from @TbSnList for xml path(''))
	exec @returnvalues=Proc_RegisterDoingSN @I_ReturnMessage=@I_ReturnMessage output, @LotSNList=@LotSNList_a,  @SP='Txn_SprayingScan_Batch' ,@Status=1 --标注此批SN正在处理 
	if @returnvalues=-1
	begin
		return -1
	END

 	
	----20140517 xuzl 锡膏条码绑定PCB条码 Begin --add by luoll 20150421 所有工单都需要管控锡膏，出锡膏房24小时内才能用，且绑定PCB条码
	DECLARE @IsCheckinol BIT=0
	--IF @MOName IN ('MO010214050307','MO010214050312','MO010214050353','MO010214050384','MO010214030070',
 --                  'MO010214030072','MO010214030686','MO010214050326','MO010214050020')
	--BEGIN
		SET @IsCheckinol=1
	--end
	IF @IsCheckinol=1
	BEGIN
		DECLARE @TinolSN1 NVARCHAR(50)
		DECLARE @WorkcenterName NVARCHAR(50)
		DECLARE @CountPre INT
		
		
		IF ISNULL(@TinolSN,'')=''
		BEGIN
	 		 set @I_ExceptionFieldName='SNScan'
			 set @I_ReturnMessage='ServerMessage: 锡膏条码不能为空！'
			 
			-- DELETE lot where ProductionLot=@V_RULE
			 return -1
		END
		
		IF NOT EXISTS(SELECT TOP 1 1 FROM dbo.TinolInfo  WITH(NOLOCK)  WHERE TinolSN=@TinolSN)
		BEGIN
	 		 set @I_ExceptionFieldName='SNScan'
			 set @I_ReturnMessage='ServerMessage: 系统中不存在锡膏条码！'+ISNULL(@TinolSN,'N/A')
			 
			 return -1
		END
 
		--SELECT TOP 1 @TinolSN1=TinolSN 
		--FROM dbo.AccessoryControl WITH(NOLOCK) 
		--WHERE MoID=@MOId AND ResourceID=@I_ResourceId 
		--ORDER BY CreateDate DESC
		
		--SELECT @CountPre=COUNT(1) FROM dbo.AccessoryControl WITH(NOLOCK)  WHERE MoID=@MoID AND TinolSN=@TinolSN1
		
		 --IF @CountPre>=200000
		 --BEGIN
	 	--	 set @I_ExceptionFieldName='SNScan'
			-- set @I_ReturnMessage='ServerMessage:当前锡膏条码已经达到设置数量：[2000]，请重新绑定锡膏条码！'
			 
			---- DELETE lot where ProductionLot=@V_RULE
			-- return -1
		 --END
		 
		--不管控数量，改为管控锡膏出锡膏房的时间，add by luoll 20150421
		--
		
		--管控锡膏上线24小时内方能使用,且检查锡膏上线工单\线体与欲绑定的工单\线体是否一致---------------------add by luoll 20150421
		DECLARE @MOName2 NVARCHAR(50) =NULL--锡膏上线的工单
		DECLARE @SMTLineNO2 NVARCHAR(50)=NULL--锡膏上线的线体

		SELECT @WorkcenterName=ISNULL(WorkcenterName,'N/A') FROM dbo.WorkCenter WITH(NOLOCK) WHERE WorkcenterId=@WorkcenterId

		--SELECT TOP 1 @MOName2=ISNULL(MOName,''),@SMTLineNO2=ISNULL(SMTLineNO,'') FROM dbo.TinolOnLine WITH(NOLOCK) 
		--	INNER JOIN dbo.MO WITH(NOLOCK) ON MO.MOId = TinolOnLine.MOID
		--	WHERE TinolSN=@TinolSN AND TinolStatus = 4 AND DATEDIFF(HOUR,TinolDate,GETDATE())<24

		IF EXISTS(SELECT 1 FROM dbo.TinolControlFlow WHERE TinolSN = @TinolSN)  --20151210 update by qindl
		BEGIN
				--DECLARE @time DATETIME	
				--DECLARE @OnLineTime INT   
				----20151211 update by jianghe
				--SELECT @time= MAX(Createdate) FROM TinolControlFlow WHERE TinolSN=@TinolSN  AND SpecificationId = 'SPE1000000HE'
				--SELECT  @OnLineTime = DATEDIFF (MINUTE,MIN(OperateTime),GETDATE()) FROM  TinolControlFlow WHERE TinolSN=@TinolSN AND SpecificationId = 'SPE1000000HG' AND Createdate > @time
				--IF @OnLineTime <24*60 AND EXISTS(SELECT 1 FROM TinolControlFlow WHERE  TinolSN = @TinolSN AND  SpecificationId='SPE1000000HH' AND OperateTime IS   NULL)
				--BEGIN
				--	SELECT  TOP 1   @MOName2= MOName,@SMTLineNO2 = WorkcenterName 
				--	 FROM   TinolControlFlow lot  INNER JOIN dbo.MO ON MO.MOId = Lot.MOId INNER JOIN dbo.WorkCenter ON lot.WorkcenterId = WorkCenter.WorkcenterId
				--	 WHERE TinolSN = @TinolSN AND lot.SpecificationId='SPE1000000HG' AND OperateTime IS  NOT NULL
				--	 ORDER BY lot.createdate DESC

				--END
				DECLARE @time DATETIME	
				DECLARE @OnLineTime INT
				DECLARE @CanOnlineTime INT=24*60 --能够上线的时间，默认为24*60  20160918 add by qindl
				DECLARE @HWTime INT --回温时间
				DECLARE @TinolCount INT

				DECLARE @VendorId CHAR(12)--锡膏条码对应的PO的供应商ID  20160918 by qindl
				SELECT @VendorId=poitem.VendorId FROM   POITEM WITH(NOLOCK)INNER JOIN dbo.POItemLot  WITH(NOLOCK) ON POItemLot.POItemId = POItem.POItemId
					WHERE LotSN=@TinolSN  --锡膏条码对应的POitem的供应商ID   由于一个po可能打两个供应商的锡膏条码.故此改动 update 20180316 by zhengyi
				
				SELECT @time= MAX(Createdate),@HWTime=DATEDIFF (MINUTE,MAX(OperateTime),GETDATE()) FROM TinolControlFlow WHERE TinolSN=@TinolSN  AND SpecificationId = 'SPE1000000HE'

				IF ISNULL(@VendorId,'')IN ('VEN100000G6U','VEN100000JVO')--add by qindl 20160918 这两个供应商对应的为OPPO 要求一次上线时间小于24小时-回温时间 且小于12小时;回收后上线不能超过8小时或回温加上线不能超过12小时
				BEGIN
					SET @CanOnlineTime=CASE WHEN 24*60-ISNULL(@HWTime,0)>12*60 THEN 12*60 ELSE 24*60-ISNULL(@HWTime,0) END 
				END

				SELECT  @TinolCount = COUNT(1) FROM TinolControlFlow WHERE TinolSN=@TinolSN AND SpecificationId = 'SPE1000000HE' 
				IF @TinolCount>1 --add by qindl 20160918 表明回收过 
				BEGIN
					IF ISNULL(@VendorId,'')IN ('VEN100000G6U','VEN100000JVO') --add by qindl 20160918 OPPO客户要求回收后上线不能超过8小时或回温加上线不能超过12小时
					BEGIN
						SET @CanOnlineTime=CASE WHEN 12*60-ISNULL(@HWTime,0)>8*60 THEN 8*60 ELSE 12*60-ISNULL(@HWTime,0) END 
					END
					ELSE --IF ISNULL(@VendorId,'')IN (SELECT VendorId FROM dbo.Vendor WHERE VendorDescription LIKE '%华为%')
					BEGIN
						SET @CanOnlineTime=8*60
					END
				END

				SELECT  @OnLineTime = DATEDIFF (MINUTE,MIN(OperateTime),GETDATE()) FROM  TinolControlFlow WHERE TinolSN=@TinolSN AND SpecificationId = 'SPE1000000HG' AND Createdate > @time

				IF @OnLineTime >=@CanOnlineTime
				BEGIN
					set @I_ExceptionFieldName='SNScan'
					SET @I_ReturnMessage = 'ServerMessage: 系统中锡膏编号【'+@TinolSN+' 】上线时间【'+CONVERT(NVARCHAR(20),@OnLineTime)+'】分钟大于可上线时间【'+CONVERT(NVARCHAR(20),@CanOnlineTime)+'】分钟，不能使用';
					RETURN -1
                END
				IF NOT EXISTS(SELECT 1 FROM TinolControlFlow WHERE  TinolSN = @TinolSN AND  SpecificationId='SPE1000000HH' AND OperateTime IS   NULL)--分开先判断为什么不行
				BEGIN
					set @I_ExceptionFieldName='SNScan'
					SET @I_ReturnMessage = 'ServerMessage: 系统中锡膏编号【'+@TinolSN+' 】没有上线，不能使用!';
					RETURN -1
				END

				IF @OnLineTime <@CanOnlineTime AND EXISTS(SELECT 1 FROM TinolControlFlow WHERE  TinolSN = @TinolSN AND  SpecificationId='SPE1000000HH' AND OperateTime IS   NULL)--update by qindl 20160918 24改为@CanOnlineTime
				BEGIN
					SELECT  TOP 1   @MOName2= MOName,@SMTLineNO2 = WorkcenterName 
					 FROM   TinolControlFlow lot  INNER JOIN dbo.MO ON MO.MOId = Lot.MOId INNER JOIN dbo.WorkCenter ON lot.WorkcenterId = WorkCenter.WorkcenterId
					 WHERE TinolSN = @TinolSN AND lot.SpecificationId='SPE1000000HG' AND OperateTime IS  NOT NULL
					 ORDER BY lot.createdate DESC

				END

		END
		ELSE
		BEGIN
			SELECT TOP 1 @MOName2=ISNULL(MOName,''),@SMTLineNO2=ISNULL(SMTLineNO,'') FROM dbo.TinolOnLine WITH(NOLOCK) 
				INNER JOIN dbo.MO WITH(NOLOCK) ON MO.MOId = TinolOnLine.MOID
				WHERE TinolSN=@TinolSN and TinolStatus =4 AND DATEDIFF(HOUR,TinolDate,GETDATE())<24
		END
		
		IF ISNULL(@MOName2,'')=''
		BEGIN
			set @I_ExceptionFieldName='SNScan'
			SET @I_ReturnMessage = 'ServerMessage: 系统中锡膏编号【'+@TinolSN+' 】没有上线,或上线时间已超过24小时，不能使用!';
			return -1
		END

		IF ISNULL(@MOName2,'NA')<>ISNULL(@MOName,'NB') --OR ISNULL(@SMTLineNO2,'NA')<>ISNULL(@WorkcenterName ,'NB')
		BEGIN
			set @I_ExceptionFieldName='SNScan'
			SET @I_ReturnMessage = 'ServerMessage: 系统中锡膏编号【'+@TinolSN+' 】已经在线别为【'+@SMTLineNO2+'】  工单为:【'+@MOname2+'】中使用,且还未满24小时!';
			return -1
		END


		--管控锡膏上线24小时内方能使用......---------------------------------------------------------------add by luoll 20150421
	end
	----20140517 xuzl 锡膏条码绑定PCB条码 End	
	Declare @SpecificationID char(12)
	Declare @WorkflowstepID char(12)
	
	-----------------------------------------------------------
	----插入到Lot表中，并传送
	Declare @MOItemID char(12)
	Declare @LotIndate datetime
	if not exists(select 1 from Lot with(nolock) inner join @TbSnList TbSn on lot.LotSN=TbSn.Lotsn  )
	Begin
		select  top 1 
		@ProductId=MOItem.ProductId,
		@MOItemId=MOItemId,
		@WorkflowID = MO.WorkflowID
		from MOItem with(nolock) inner join MO with(nolock) ON MOItem.MOId = MO.MOID
		where MO.MOId = @MOID and bomlevel = 0 and linesequence ='0'
		
		EXEC	@return_value = [dbo].[TxnBase_LotStart_Batch]
		@I_ReturnMessage = @I_ReturnMessage OUTPUT,
		@I_PlugInCommand = @I_PlugInCommand ,
		@I_OrBitUserId = @I_OrBitUserId,
		@I_ResourceId = @I_ResourceId,
		@ListLotId = @ListLotId OUTPUT,
		@ListLotSN = @LotSNList,
		@StartReasonId='URC1000000B7' , --计划性批号正常启动
		@ProductId =@ProductId,
		@Qty = 1,
		@WorkflowId = @WorkflowId,
		@MOId=@MOId,
		@MOItemId=@MOItemId,
		@UserComment=''
 	
		IF @return_value<> -1
		begin
			set @lotInDate = GETDATE()
			--3.传送批号
			while @i<=@count
			begin
				select @LotSN=TbSn.Lotsn from @TbSnList TbSn where RowNum=@i
				EXEC [dbo].[TxnBase_LotMove] 
					@I_ReturnMessage=@I_ReturnMessage OUTPUT,
					@I_OrBitUserId =@I_OrBitUserId ,
					@I_ResourceId =@I_ResourceId ,
					@LotSN =@LotSN,
					@lotInDate = @lotInDate
					
				set	@i=@i+1
			end
		end
	end
			
 -- add by ybj 20150224
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_debug_7', @debug+'_'+@MOName )
	
	update @TbSnList set LotId=lot.LotId, 
		SpecificationId=lot.SpecificationId,
		WorkflowStepId=lot.WorkflowStepId,
		WorkflowID=lot.WorkflowId
		from lot  with(nolock) inner join @TbSnList TbSn on lot.LotSN=TbSn.Lotsn
	

	--得到产品ID
	set @ProductId =''
	select @ProductId = ProductId,@MOQtyRequired = MOQtyRequired  from MO with(nolock) where MOId = @MOId
	
	------计算PCB板扣数
	--if isnull(@PCBSN,'') <> ''
	--Begin
	--	Set @PCBQty = @PCBQty - @MakeupCount
	--	if  isnull(@PCBQty,0) < 0
	--	begin
	--		set @I_ReturnMessage='ServerMessage:此PCB板序列号数量已用完，请更换物料！'
	--		return -1
	--	end
	--end
	----生成连扳条码(A1+两位年+1位月+1位日+小时+分钟+秒)
	
	set 	@I_ReturnMessage=''
	EXEC	[dbo].[SNApplySNDoMethod] --产生连板号           
				@I_ReturnMessage = @I_ReturnMessage OUTPUT,
				@I_ExceptionFieldName = @I_ExceptionFieldName OUTPUT,
				@MOId =@MOId,
				@SNRuleName ='ProductionLot',
				@NewOutSN = @V_RULE OUTPUT	
	
	if ISNULL(@V_RULE,'')=''
	begin
		set @I_ReturnMessage='ServerMessage: 产生连板号出错请重新提交! '
		return -1
	end
	----------------------------------
	--SET @Sql='UPDATE dbo.Lot
	--	SET Lot.ProductionLot = @V_RULE,
	--	SMTMOID=@MOId,MakeupCount= @MakeupCount '
	SET @Sql='UPDATE dbo.Lot
		SET Lot.ProductionLot ='''+@V_RULE+''',
		SMTMOID='''+@MOId+''',MakeupCount='+convert(nchar(10),@MakeupCount)
	
		IF ISNULL(@SNType,'N/A')='PCBASN'
		 BEGIN
			SET @Sql=@Sql+' ,VendorLotSN = UPPER(lot.lotSN) '
		 END	
		ELSE IF ISNULL(@SNType,'N/A')='MAC'
		 BEGIN
			SET @Sql=@Sql+' ,MAC = UPPER(lot.lotSN) '
		 END	
		if isnull(@PCBType,'') = 'AB面板' 
		 Begin
			SET @Sql=@Sql+' ,ABSide = '''+@ABSide+''' '
		 END
		ELSE if  @PCBType = '阴阳板' 
		 BEGIN
			IF @count<=@ASideQty
			 BEGIN
				 SET @Sql=@Sql+' ,ABSide = ''A'' '
			 END
			ELSE
			 BEGIN
				SET @Sql=@Sql+' ,ABSide = ''B'' '
			 END
		 END
--UPDATE dbo.Lot
--		SET Lot.ProductionLot ='link13121600038',
--		SMTMOID='MOD100001XWB',MakeupCount=4          ,
--		VendorLotSN = UPPER(lot.lotSN)  ,ABSide = 'A'  
--		from lot inner join 
--		@TbSnList TbSn  on lot.LotSN=TbSn.Lotsn 
	select * into #temTb from @TbSnList
	
	SET @Sql=@Sql+' from lot with(nolock) inner join #temTb TbSn  on lot.LotSN=TbSn.Lotsn '
	
	exec (@sql) 
	drop table #temTb
	--EXEC sys.sp_executesql @Sql,N'@V_RULE nvarchar(50),@MOId char(12),@MakeupCount int',
	--		                             @V_RULE,@MOId,@MakeupCount
 	
	declare  @PKDataSet  table  ( --主键表用以保存指定表的主键ID
	RowNum int,
	PkID char(12)
	)	
	INSERT  INTO  @PKDataSet 
	EXEC SysGetBatchObjectPKId @ObjectName='DataChainPCBStart' ,@RowCount=@count --取指定数量的Lot表主键id
	
	if not exists(select tbSn.LotId from DataChainPCBStart with(nolock) inner join @TbSnList tbSn on DataChainPCBStart.LotID=tbSn.LotId)
	Begin
		insert into DataChainPCBStart(
		DatachainPCBStartID,
		DataChainID,
		LotID,
		PCBLotID,
		startCount,
		UserID,
		MOID,
		createdate)
		select 
		pk.PkID,
		'',
		TbSn.LotId,
		@PCBLotID,
		1,
		@I_OrBitUserId,
		@MOId,
		GETDATE()
		from 
		@TbSnList TbSn inner join @PKDataSet PK on tbsn.RowNum=pk.RowNum
	End
	else 
	begin
		set @I_ReturnMessage='ServerMessage: 批号：'+rtrim(@LotSNList)+'   已经过上线扫描'
		return -1
	end
	-- add by ybj 20150224
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_debug_8', @debug +'_'+@MOName)
	----20140517 xuzl 锡膏条码绑定PCB条码 Begin
	/*插入记录表*/
	IF @IsCheckinol=1
	BEGIN
		DECLARE @AccessoryControlID CHAR(12)
		
		DECLARE  @PKDataSetzl  table  ( --主键表用以保存指定表的主键ID
							RowNum int,
							PkID char(12)
						)	
						insert into @PKDataSetzl 
						EXEC SysGetBatchObjectPKId @ObjectName='AccessoryControl' ,@RowCount=@count 
		 
 
		 INSERT INTO dbo.AccessoryControl
				 ( AccessoryControlID ,
				   LotID ,
				   MoID ,
				   TinolSN ,
				   ResourceID ,
				   UesrID ,
				   CreateDate
				 )
				 SELECT pk.PkID,
						tb.lotid,
						@MoID,
						@TinolSN,
						@I_ResourceId,
						@I_OrBitUserId,
						GETDATE() 
				 FROM @TbSnList tb 
				 INNER  JOIN  @PKDataSetzl pk 
				 ON tb.RowNum=pk.RowNum
 
		         
		 DECLARE   @DataChainIdZL CHAR(12)    
		 DECLARE   @M INT=1 
		while @M<=@count
		begin
			select @LotSN=TbSn.Lotsn,@LotId=LotId from @TbSnList TbSn where RowNum=@M
			BEGIN TRY 
				EXEC	[dbo].[TxnBase_DataChainMainLine]
					@DataChainId = @DataChainIdZL OUTPUT,
					@TxnCode ='DC',
					@I_PlugInCommand = @I_PlugInCommand,
					@I_OrBitUserId = @I_OrBitUserId,
					@I_ResourceId = @I_ResourceId,
					@LotId = @LotId,
					@MOId=@MOId,
					@ProductId = @ProductId,
					@ShiftId = '',
					@WorkcenterId = @WorkcenterId,
					@SpecificationId = @SpecificationId,
					@WorkflowStepId = @WorkflowStepId,
					@UserComment = '锡膏条码绑定PCS板Log'
			END TRY	
			BEGIN CATCH
			    
				INSERT INTO dbo.CatchErooeLog
				        ( ProcName, ErooeCommad, CreateDate )
				VALUES  ( N'Txn_SprayingScan_Batch_8.1', -- ProcName - nvarchar(50)
				         '['+@LotSN+']' +  ISNULL(ERROR_MESSAGE(), '') , -- ErooeCommad - nvarchar(500)
				          GETDATE()  -- CreateDate - datetime
				          )
			END CATCH	

	        BEGIN TRY
				UPDATE 	AccessoryControl SET DataChainId=@DataChainIdZL WHERE LotID=@LotId
			END TRY	
			BEGIN CATCH
			    
				INSERT INTO dbo.CatchErooeLog
				        ( ProcName, ErooeCommad, CreateDate )
				VALUES  ( N'Txn_SprayingScan_Batch_8.2', -- ProcName - nvarchar(50)
				         '['+@LotSN+']' +  ISNULL(ERROR_MESSAGE(), '') , -- ErooeCommad - nvarchar(500)
				          GETDATE()  -- CreateDate - datetime
				          )
			END CATCH
			set	@M=@M+1
		end
	END
	----20140517 xuzl 锡膏条码绑定PCB条码 End
 
	-- add by ybj 20150224
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_debug_9', @debug +'_'+@MOName)
	if exists(select 1 from MO with(nolock) where moid = @MOId AND executedatefrom IS NULL)
     BEGIN
		Update mo set MO.executedatefrom = GETDATE() where MOId = @MOID
     END
     ----记录到DataChainAssyIssue表中----
	declare @AssyTxnCode varchar(10)
	declare @IssueTxnCode varchar(10)

	set @AssyTxnCode='SMTASSY'
	set @IssueTxnCode='SMTISSUE'
	
	--生成装配Lot的主数据链ID
	--申请主PKID	
	declare @DataChainId char(12)
	declare @AssyDataChainId char(12)	
    set @i=1	--重置循环下标
    while @i<=@count
    begin
		select @LotID=TbSn.LotId,@lotsn=TbSn.Lotsn, @WorkflowstepID=TbSn.WorkflowStepId,
			@SpecificationId=TbSn.SpecificationId
			from @TbSnList TbSn where TbSn.RowNum=@i
			
		--产生AssyDataChain返回数据链Id
		EXEC	[dbo].[TxnBase_DataChainMainLine]
		@DataChainId = @AssyDataChainId OUTPUT,
		@TxnCode =@AssyTxnCode,
		@I_PlugInCommand = @I_PlugInCommand,
		@I_OrBitUserId = @I_OrBitUserId,
		@I_ResourceId = @I_ResourceId,
		@LotId = @LotId,
		@MOID = @MOID,
		@ProductId = @ProductId,
		@Qty = 1,
		@WorkcenterId = @WorkcenterId,
		@SpecificationId = @SpecificationId,
		@WorkflowStepId = @WorkflowStepId
 
		Declare @DataChainAssyIssueId char(12)
		Declare @IssueDataChainId char(12)
		
		
		
		IF @IsHuaWeiCustomer='true' --如果是华为客户,上传记录到华为表
		 BEGIN
			  begin try 
				EXEC dbo.Interface_HuaWei_IINVSUMTMP4D_new 
				    @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
					@RAW_LOT_ID = @PCBSN, -- nvarchar(128)
					@EMS_ORDER_ID = @MOName, -- nvarchar(25)
					@LOT_ID = @LotSN, -- nvarchar(30)
					@USE_QTY = 1 -- decimal
					
					--INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_Huawei',@LotSN+','+@PCBSN) -- add by ybj 20141017
			 END TRY
			 begin catch
				
				insert into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_Huawei',ISNULL(ERROR_MESSAGE(),'华为客户上线出现异常')+ ' ' + ISNULL(@I_ReturnMessage,'')) -- add by ybj 20141017
				
			 END catch
		end 
	    --================================================-----------------------
		--IF @IsHuaWeiCustomer='true' --如果是华为客户,上传记录到华为表
		-- BEGIN
		--	begin try 
		--		EXEC dbo.Interface_HuaWei_IINVSUMTMP @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
		--			@RAW_LOT_ID = @PCBSN, -- nvarchar(128)
		--			@EMS_ORDER_ID = @MOName, -- nvarchar(25)
		--			@LOT_ID = @LotSN, -- nvarchar(30)
		--			@USE_QTY = 1 -- decimal
		--	end try
		--	begin catch
		--		declare @body nvarchar(100)
		--		set @body=isnull(@LotSN,'')+':'+isnull(@V_RULE,'N/A1')
				
		--		--将收件人、抄送人设为变量 by haomj  2014.12.10
	
		--		SELECT @recipients=MAIL_TO+';',@copy_recipients=copy_recipients FROM dbo.SYS_S_CUST_MAIL with(nolock) WHERE  CUST_ID='MES_ADMIN' 
		--		exec [Send_Mail1] 
		--		@recipients 
		--		,@copy_recipients
		--		,@subject='华为客户上线出现异常'
		--		,@body=@body
				
		--		DELETE lot where ProductionLot=isnull(@V_RULE,'N/A1')
		--		set @I_ReturnMessage='ServerMessage:华为客户上线出现异常'+ISNULL(@LotSN,'N/A')+'请重新上线!!'
		--		insert into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_Huawei',ISNULL(ERROR_MESSAGE(),'华为客户上线出现异常')+ ' ' + ISNULL(@I_ReturnMessage,'')) -- add by ybj 20141017
		--		return -1
		--	end catch
		
		-- END
		 --================================================-----------------------
		 
		 --生产Issue主线
        
		EXEC	[dbo].[TxnBase_DataChainMainLine]
		@DataChainId = @IssueDataChainId OUTPUT,
		@TxnCode =@IssueTxnCode,
		@I_PlugInCommand = @I_PlugInCommand,
		@I_OrBitUserId = @I_OrBitUserId,
		@I_ResourceId = @I_ResourceId,
		@LotId = @PCBLotID,
		@MOID = @MOID,
		@ProductId = @PCBProductID,
		@Qty = 1,
		@WorkcenterId = @WorkcenterId,
		@SpecificationId = @SpecificationId,
		@WorkflowStepId = @WorkflowStepId
	
		update @TbSnList set AssyDataChainId=@AssyDataChainId,
			IssueDataChainId=@IssueDataChainId where RowNum=@i
		set @Date = GETDATE()
		----3.传送批号
		EXEC [dbo].[TxnBase_LotMove] 
		@I_ReturnMessage=@I_ReturnMessage OUTPUT,
		@I_OrBitUserId =@I_OrBitUserId ,
		@I_ResourceId =@I_ResourceId ,
		@LotSN =@LotSN ,
		@lotInDate = @Date
			
		set @i=@i+1
    end
    delete @PKDataSet
    insert into @PKDataSet 
	EXEC SysGetBatchObjectPKId @ObjectName='DataChainAssyIssue' ,@RowCount=@count --取指定数量的Lot表主键id
 
    --装配明细 
			insert into DataChainAssyIssue  (
			DataChainAssyIssueId,
			AssyDataChainId,
			IssueDataChainId,
			AssyIssueType,
			AssyLotId,
			IssueLotId,
			AssyMOId,
			IssueMOId,
			IssueQty,
			AssyMOItemId,
			IssueProductId,
			ResourceId,
			UserId,
			SpecificationId,
			WorkflowStepId,
			IsReplaceProduct
			)
			SELECT 
			PK.PkID,
			AssyDataChainId,
			IssueDataChainId,
			'',
			LotId,
			@PCBLotID,
			@MOID,
			@MOID,
			1,
			@MOItemID,
			@PCBProductID,
			@I_ResourceId,
			@I_OrBitUserId,
			SpecificationId,
			WorkflowStepId,
			'0'
			FROM @TbSnList TbSn inner join @PKDataSet PK 
				on TbSn.RowNum=PK.RowNum
				
 
				
    	--计算PCB板扣数
		if isnull(@PCBSN,'') <> ''
		Begin
			
			update Lot set Lot.Qty = lot.Qty - @MakeupCount  where lot.LotId = @PCBLotID
		End
		
	----计算工单已扫描数
	
	--
      IF EXISTS (SELECT *FROM moitem where MOId=@MOId and ProductId=@ProductId  and isnull(IsStartLot,0)=0)
      begin 
	
	    select @MOScanCount = COUNT(LotId) from Lot with(nolock) where SMTMOID = @MOId and ProductId=@ProductId and Isnull(ProductionLot,'') <> ''
	     update moitem  set IsStartLot=@MOScanCount  where MOId=@MOId and ProductId=@ProductId 
	end 
	 else 
	 begin 
	    select @MOScanCount=IsStartLot from moitem with(nolock) where MOId=@MOId and ProductId=@ProductId
	 
	 end 
	SET @ScanCount =0
 
	select @PCBQty = Lot.Qty from Lot with(nolock)where lot.LotId = @PCBLotID
	-- add by ybj 20150224
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_debug_10', @debug+'_'+@MOName )

	  DECLARE  @productid_4d CHAR(12)
	  SELECT  @productid_4d=ProductId  FROM  dbo.MO  WITH(NOLOCK) WHERE MOId=@moid
	  IF  EXISTS(SELECT  1 FROM yy_4d  WHERE productid=@productid_4d)
	  BEGIN
	     INSERT  INTO  yylotsn_4d
		 (Lotsns ,productionlot,
		 Createdate )
		 VALUES(@LotSNList4d,@V_RULE,GETDATE())
	  END

	exec @returnvalues=Proc_RegisterDoingSN @I_ReturnMessage=@I_ReturnMessage output, @LotSNList=@LotSNList_a,  @SP='Txn_SprayingScan_Batch' ,@Status=0 --标注此批SN已处理完成
 
	select @MOScanCount as MOScanCount,@ScanCount as ScanCount,'' as HideSN,@PCBQty AS PCBQTY
	-- add by ybj 20150224
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SprayingScan_Batch_debug_11', @debug +'_'+@MOName)
	
	--反查健壮判断
	DECLARE  @lotsn_end  NVARCHAR(100)
	SELECT  TOP 1 @lotsn_end=id FROM dbo.SQL_split(@LotSNList4d,',')
	IF  EXISTS  (SELECT NULL FROM  lot WITH(NOLOCK)  WHERE lotsn=@lotsn_end AND ISNULL(SpecificationId,'')='')
	BEGIN   
	    INSERT  INTO  dbo.yylotsn_4d
	            ( Lotsns ,
	              productionlot ,
	              Aside_lots ,
	              Createdate
	            )
	    VALUES  ( @LotSNList4d , -- Lotsns - nvarchar(max)
	              N'null_spec' , -- productionlot - nvarchar(50)
	              N'' , -- Aside_lots - nvarchar(300)
	              GETDATE()  -- Createdate - datetime
	            )

			--删除节点异常的批号 2017-08-25
		    DELETE lot WHERE LotSN in (SELECT id from dbo.SQL_split(@LotSNList4d,','))
			SET @I_ReturnMessage = 'ServerMessage: 上线失败,但出现规程为空异常,已经删除，请重新扫描上线！';
			return -1
	END	
	--反查健壮判断


	return 0	
    
end


