using UnityEditor;
using UnityEngine;
using CoffeeBean.EditorTools;

namespace CoffeeBean.Build.Demo
{
    /// <summary>
    /// NativeExportDemo 示例：演示 com.coffeebean.build 的用法。
    /// 入口：Tools &gt; CoffeeBean &gt; Build Demo（Android/iOS 各一条 dry-run）。
    /// dry-run 在临时 fake 导出工程上跑完整管线，不触发真构建、不落盘。
    /// </summary>
    public static class NativeExportDemo
    {
        [MenuItem("Tools/CoffeeBean/Build Demo/Android (dry-run)")]
        public static void DemoAndroid()
        {
            Debug.Log("[Demo] " + NativeExportDemoRunner.RunDemo(CExportPlatform.Android));
        }

        [MenuItem("Tools/CoffeeBean/Build Demo/iOS (dry-run)")]
        public static void DemoIOS()
        {
            Debug.Log("[Demo] " + NativeExportDemoRunner.RunDemo(CExportPlatform.IOS));
        }

        [MenuItem("Tools/CoffeeBean/Build Demo/打开配置资产")]
        public static void OpenConfig()
        {
            CExportConfigAsset.CreateOrFocusAsset();
        }
    }
}
