package com.example.testchart.view;

import java.util.List;

import org.achartengine.ChartFactory;
import org.achartengine.GraphicalView;
import org.achartengine.chart.PointStyle;
import org.achartengine.model.XYMultipleSeriesDataset;
import org.achartengine.renderer.XYMultipleSeriesRenderer;

import android.content.Context;
import android.content.Intent;

public class PmChartView extends AbstractDemoChart {

	String name, desc;
	XYMultipleSeriesDataset pmDataset;
	XYMultipleSeriesRenderer pmRenderer;

	@Override
	public String getName() {

		return name;
	}

	@Override
	public String getDesc() {

		return desc;
	}

	private PmChartView() {
	}

	public PmChartView(String name, String desc) {

		this.name = name;
		this.desc = desc;
	}

	public XYMultipleSeriesDataset initDataset(
			String[] titles, List<double[]> xValues, List<double[]> yValues)
			throws Exception {
		

		try {
			pmDataset = buildDataset(titles, xValues, yValues);
		} catch (Exception e) {
			throw new Exception(
					"please check titles or xValues or yValues is current");
		}

		return pmDataset;

	}

	public XYMultipleSeriesRenderer initRenderer(int[] colors,
			PointStyle[] styles) throws Exception {

		try {
			pmRenderer = buildRenderer(colors, styles);
		} catch (Exception e) {
			throw new Exception("please check colors or styles is current");
		}

		return pmRenderer;

	}

	@Override
	public GraphicalView executeForView(Context context) {

		GraphicalView graphicalView = ChartFactory.getLineChartView(context,
				pmDataset, pmRenderer);

		return graphicalView;
	}

	@Override
	public Intent execute(Context context) {
		
		return  ChartFactory.getLineChartIntent(context,
				pmDataset, pmRenderer);
	}

}
