using UnityEngine;

namespace CoffeeBean.DI.Demo
{
    // ========== 示例服务 ==========

    public interface ILogger { void Log(string msg); }
    public class ConsoleLogger : ILogger { public void Log(string msg) => Debug.Log("[DI] " + msg); }

    public interface IPlayerStats { int Level { get; set; } }

    public class PlayerStats : IPlayerStats
    {
        public int Level { get; set; } = 1;
    }

    /// <summary>依赖 ILogger + IPlayerStats（构造注入）。</summary>
    public class GameManager
    {
        private readonly ILogger _logger;
        public readonly IPlayerStats Stats;

        [CDIInject] public ILogger FieldLogger; // 字段注入示例

        public GameManager(ILogger logger, IPlayerStats stats)
        {
            _logger = logger;
            Stats = stats;
        }

        public void Report()
        {
            _logger.Log($"GameManager: 等级 {Stats.Level}（字段注入 logger: {FieldLogger != null}）");
        }
    }

    /// <summary>
    /// 依赖注入示例（场景挂载后运行）：
    /// 注册 → 解析 → 构造/字段注入 → 单例/瞬时 → 子作用域。
    /// </summary>
    public sealed class DiDemo : MonoBehaviour
    {
        private void Start()
        {
            var container = new CDIContainer();

            // 注册
            container.Bind<ILogger>().To<ConsoleLogger>(CDILifetime.Singleton);
            container.Bind<IPlayerStats>().To<PlayerStats>(CDILifetime.Singleton);
            container.Bind<GameManager>().ToSelf();

            // 解析（构造注入 ILogger + IPlayerStats；字段注入 FieldLogger）
            var gm = container.Resolve<GameManager>();
            gm.Report();

            // 单例：同一实例
            var gm2 = container.Resolve<GameManager>();
            Debug.Log($"[DI] 单例复用: {gm == gm2}（GameManager 是 Transient，但内部依赖是 Singleton）");

            // 子作用域
            using var scope = container.CreateScope();
            var scopedGm = scope.Resolve<GameManager>();
            Debug.Log($"[DI] 子作用域可解析父容器: {scopedGm != null}");
        }
    }
}
