using UnityEngine;

namespace CoffeeBean.Input.Demo
{
    /// <summary>
    /// 输入抽象示例（场景挂载后运行，含 CInputDriver 组件或手动 Update）：
    /// 注册动作 → 查询（GetActionDown/GetAction/GetActionUp）+ 事件。
    /// 键盘 / 鼠标 / 触屏统一为动作名，业务不关心具体键位。
    /// </summary>
    public sealed class InputDemo : MonoBehaviour
    {
        private int _jumpCount;

        private void Awake()
        {
            // 注册动作（改键位只改这里）
            CInput.Register(new CInputAction("Jump").BindKey(KeyCode.Space).BindKey(KeyCode.W).BindTouch());
            CInput.Register(new CInputAction("Fire").BindMouse(0));
            CInput.Register(new CInputAction("Menu").BindKey(KeyCode.Escape));

            // 事件方式
            CInput.OnActionDown += name => Debug.Log($"[InputDemo] 按下: {name}");
        }

        private void Update()
        {
            if (CInput.GetActionDown("Jump"))
            {
                _jumpCount++;
                Debug.Log($"[InputDemo] 跳跃（查询 API），次数 {_jumpCount}");
            }
            if (CInput.GetActionDown("Menu")) Debug.Log("[InputDemo] 菜单");
        }

        private void OnGUI()
        {
            GUILayout.BeginArea(new Rect(10, 10, 360, 120));
            GUILayout.Label("<b>Input 演示</b>");
            GUILayout.Label("空格/W/触摸 = 跳跃；鼠标左键 = 开火；Esc = 菜单");
            GUILayout.Label($"跳跃次数: {_jumpCount}（动作名查询，与键位解耦）");
            GUILayout.EndArea();
        }
    }
}
